define [
  'cord!Utils'
  'cord!utils/Future'
  'underscore'
  'postal'
  'cord!AppConfigLoader'
  'eventemitter3'
  'cord!request/errors'
], (Utils, Future, _, postal, AppConfigLoader, EventEmitter, httpErrors) ->

  class Api extends EventEmitter

    @inject: ['cookie', 'request', 'tabSync']

    # Cookie name for auth module name
    @authModuleCookieName: '_api_auth_module'

    fallbackErrors: null

    # Default auth module, check out config.api.defaultAuthModule
    defaultAuthModule: 'OAuth2'


    constructor: (serviceContainer) ->
      @fallbackErrors = {}
      @serviceContainer = serviceContainer


    init: ->
      # заберем настройки для fallbackErrors
      AppConfigLoader.ready().done (appConfig) =>
        @fallbackErrors = appConfig.fallbackApiErrors


    configure: (config) ->
      ###
      Updates API endpoint options, like host, protocol etc.
      This method is need to be called when configuration is changed.
      ###
      defaultOptions =
        protocol: 'https'
        host: 'localhost'
        urlPrefix: ''
        params: {}
        authenticateUserCallback: -> false # @see authenticateUser() method

      @options = _.extend(defaultOptions, @options, config)
      @defaultAuthModule = @options.defaultAuthModule if @options.defaultAuthModule

      @setupAuthModule()

      # если в конфиге у нас заданы параметры автовхода, то надо логиниться по ним
      if @options.autoLogin? and @options.autoPassword?
        @options.authenticateUserCallback = =>
          @getTokensByUsernamePassword @options.autoLogin, @options.autoPassword


    getBackendHost: ->
      ###
      Returns currently used api backend host
      ###
      @options.host


    setupAuthModule: ->
      ###
      Initializer. Should be called after injecting @inject services
      ###
      if @options.forcedAuthModule
        module = @options.forcedAuthModule
      else if @cookie.get(Api.authModuleCookieName)
        module = @cookie.get(Api.authModuleCookieName)
      else
        module = @defaultAuthModule

      @setAuthModule(module).catch =>
        module = @defaultAuthModule
        if not module
          throw new Error('Api unable to determine auth module name. Please check out config.api.defaultAuthModule')

        @setAuthModule(module)


    setAuthModule: (modulePath) ->
      ###
      Sets or replaces current authentication module.
      The method can be called consequently, it guarantees, that @authPromise will be resolved with latest module
      @param {String} modulePath - absolute or relative to core/auth path to Auth module
      @return {Future[<auth module instance>]}
      ###
      return Future.rejected('Api::setAuthModule modulePath needed')  if not modulePath

      originalModule = modulePath
      modulePath = "/cord/core/auth/#{ modulePath }"  if modulePath.charAt(0) != '/'

      _console.log "Loading auth module: #{modulePath}"  if global.config.debug.oauth

      localAuthPromise = Future.single("Auth module promise: #{modulePath}")
      @lastModulePath = modulePath # To check that we resolve @authPromise with the latest modulePath

      Future.require('cord!' + modulePath).then (Module) =>
        # this is workaround for requirejs-on-serverside bug which doesn't throw an error when requested file doesn't exist
        throw new Error("Failed to load auth module #{modulePath}!")  if not Module
        if @lastModulePath == modulePath # To check that we resolve @authPromise with the latest modulePath
          @cookie.set(Api.authModuleCookieName, originalModule, expires: 365)
          module = new Module(@options[Module.configKey], @cookie, @request, @tabSync)
          localAuthPromise.resolve(module)
          # bypass module event
          module.on('auth.available', => @emit('auth.available'))

      .catch (error) =>
        if @lastModulePath == modulePath # To check that we resolve @authPromise with the latest modulePath
          localAuthPromise.reject(error)
        _console.error("Unable to load auth module: #{modulePath} with error", error)

      @authPromise.when(localAuthPromise)  if @authPromise and not @authPromise.completed()
      @authPromise = localAuthPromise


    authTokensAvailable: ->
      ###
      Checks if there are stored auth tokens that can be used for authenticated request.
      @return Future{Boolean}
      ###
      if not @authPromise
        _console.warn('Api::authTokensAvailable authPromise does not exists. Call setAuthModule before use.')
        Future.resolved(false)
      else
        @authPromise.then (authModule) ->
          authModule.isAuthAvailable()
        .catch (e) ->
          _console.warn('authTokensAvailable failed, because of:', e)
          false


    authTokensReady: ->
      ###
      Returns a promise that completes when auth tokens are available and authenticated requests can be done
      @return {Future[undefined]}
      NOTE! returned future does not guarantee to be resolved ever.
      Please, checkout authTokensAvailable() and authenticateUser(), before using this function.
      ###
      @authTokensAvailable().withoutTimeout().then (available) =>
        if available
          _console.warn('authTokensReady: auth tokens are not available')
          true
        else
          result = Future.single('authTokensReady')
          # We can not subscribe to authModule, stored in @authPromise future, because it can be changed due to
          # user login. So, we subscribe to event, bubbled in this module.
          @once 'auth.available', =>
            result.when(@authTokensReady()) # recursively checking if auth tokens actually valid
          result


    authTokensReadyCb: (cb) ->
      ###
      Executes the given callback when auth tokens are available.
      Same as authTokensReady but with callback semantics.
      @param {Function} cb
      ###
      @authTokensAvailable().then (available) =>
        if available
          cb()
        else
          # We can not subscribe to authModule, stored in @authPromise future, because it can be changed due to
          # user login. So, we subscribe to event, bubbled in this module.
          @once 'auth.available', => @authTokensReadyCb(cb) # recursively checking if auth tokens actually valid
      return


    authByUsernamePassword: (username, password) ->
      ###
      Tries to authenticate by username and password
      @param {String} username
      @param {String} password
      @return {Future} resolves when auth suceeded, fails in otherwa
      ###
      @authPromise.then (authModule) ->
        authModule.grantAccessByUsernamePassword(username, password)


    authenticateUser: ->
      ###
      Initiates pluggable via authenticateUserCallback-option authentication of the user and waits for the global
       event with the auth-tokens which must be triggered by that procedure.
      Callback-function-option authenticateUserCallback must return boolean 'true' if authentication can be performed
       without user interaction, or boolean 'false' if user interaction is required (for example, login form submission)
       and authentication wait time is not determined.
      @return {Future} resolves when auth become available
      ###
      @authPromise.then (authModule) =>
        # Clear Cookies
        authModule.clearAuth()
        authModule.tryToAuth().catch (e) =>
          _console.log("Api::authenticateUser authModule.tryToAuth failed with: #{JSON.stringify(e)}")
          if @options.authenticateUserCallback()
            @authTokensReady()
          else
            Future.rejected(e)


    get: (url, params, callback) ->
      if _.isFunction(params)
        callback = params
        params = {}
      @send 'get', url, params, (response, error) =>
        if error
          setTimeout =>
            @send 'get', url, params, callback
          , 10
        else
          callback?(response, error)


    post: (url, params, callback) ->
      @send 'post', url, params, callback


    put: (url, params, callback) ->
      @send 'put', url, params, callback


    del: (url, params, callback) ->
      @send 'del', url, params, callback


    send: (args...) ->
      ###
      High level API request method. Smartly prepares and performs API request.
      @param {String} method HTTP method
      @param {String} url Request URL (without protocol, host and prefix)
      @param {Object} params Request params
      @param {Function[response, error]} callback Callback to be called when request finished (deprecated)
      @return {Future[Object]} response
      ###
      validatedArgs = Utils.parseArguments args.slice(1),
        url: 'string'
        params: 'object'
        callback: 'function'
      validatedArgs.method = args[0]

      requestPromise =
        if validatedArgs.params.noAuthTokens
          url = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{validatedArgs.url}"
          @_doRequest(validatedArgs.method, url, validatedArgs.params, validatedArgs.params.retryCount ? 5)
        else
          @_prepareRequestArgs(validatedArgs).then (preparedArgs) =>
            @_doRequest(preparedArgs.method, preparedArgs.url, preparedArgs.params, preparedArgs.params.retryCount ? 5)

      requestPromise.done (response) ->
        validatedArgs.callback?(response)
      .fail (err) ->
        validatedArgs.callback?(err.response, err)


    _prepareRequestArgs: (args) ->
      ###
      Prepares request params for the _doRequest method, according to the current API settings.
      @param {Object} args
      @return {Future[Object]}
      ###
      @injectAuthParams(args.url, args.params).spread (url, params) =>
        method: args.method
        url:    "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{url}"
        params: _.extend({ originalArgs: args }, @options.params, params)
      .catch (e) =>
        # Auth module failed, so we need to authorize here somehow
        _console.warn("Auth failed:", e)
        @options.authenticateUserCallback() if not args.params?.skipAuth
        throw e


    prepareAuth: ->
      ###
      Try to prepare auth module to be ready for a request
      ###
      @authPromise.then (authModule) =>
        authModule.prepareAuth().catch (e) =>
          @options.authenticateUserCallback()
          throw e


    injectAuthParams: (url, params) ->
      ###
      Injects auth params to passed url and params
      ###
      @authPromise.then (authModule) => authModule.injectAuthParams(url, params)


    _doRequest: (method, url, params, retryCount = 5) ->
      ###
      Performs actual HTTP request with the given params.
      Smartly handles different edge cases (i.e. auth errors) - tries to fix them and repeats recursively.
      @param {String} method HTTP method - get, post, put, delete
      @param {String} url Fully-qualified URL
      @param {Object} params Request params according to the curly spec
      @param {Int} retryCount Maximum number of retries before give up in case of errors (where applicable)
      @return {Future[Object]} response object like in curly
      ###
      requestParams = _.clone(params)
      delete requestParams.originalArgs
      @authPromise.then (authModule) =>
        @request[method](url, requestParams).then (result, response) =>
          # If backend want to change host, override it
          # Event should be handler by api service factory
          if response.headers.has('X-Target-Host')
            @emit('host.changed', response.headers.get('X-Target-Host'))
          [result, response]

        .catchIf httpErrors.Network, (e) =>
          # In case of network error, we'll try to reconnect again
          if retryCount > 0
            _console.warn "WARNING: request to #{url} failed because of network error #{e}. Retrying after 0.5s..."
            Future.timeout(500).then =>
              @_doRequest(method, url, params, retryCount - 1)
          else
            throw e

        .catchIf httpErrors.InvalidResponse, (e) =>
          # Handle invalid server response. i.e. 401, 403, 500 and etc..
          # We can not handle here network errors, so, it will throws to external handlers
          response = e.response
          isAuthFailed = authModule.isAuthFailed(response.body)
          # if auth failed normally, we try to resuurect auth and try again
          if isAuthFailed and not params.skipAuth and retryCount > 0
            # need to use originalArgs here to workaround situation when API host is changed during request
            @_prepareRequestArgs(params.originalArgs).then (preparedArgs) =>
              @_doRequest(preparedArgs.method, preparedArgs.url, preparedArgs.params, retryCount - 1)

          # if request failed in other cases
          else
            message = response.body?._message ? response.body?.message ? response.statusText

            # Post could make duplicates
            if method == 'get' and retryCount > 0
              _console.warn "WARNING: request to #{url} failed due to invalid response. #{response} Retrying after 0.5s..."

              Future.timeout(500).then =>
                @_doRequest(method, url, params, retryCount - 1)
            else
              # handle API errors fallback behaviour if configured
              errorCode = response.statusCode
              if errorCode? and @fallbackErrors and @fallbackErrors[errorCode]
                fallbackInfo = _.clone(@fallbackErrors[errorCode])
                fallbackInfo.params = _.clone(fallbackInfo.params)
                # если есть доппараметры у ошибки - добавим их
                if response.body._params?
                  fallbackInfo.params.contentParams =
                    if not fallbackInfo.params.contentParams?
                      {}
                    else
                      _.clone(fallbackInfo.params.contentParams)
                  fallbackInfo.params.contentParams['params'] = response.body._params

                @serviceContainer.get('fallback').fallback(fallbackInfo.widget, fallbackInfo.params)

              # otherwise just notify the user
              else
                message = 'Ошибка ' + (if response.statusCode != undefined then (' ' + response.statusCode)) + ': ' + message
                postal.publish 'error.notify.publish',
                  link: ''
                  message: message
                  error: true
                  timeOut: 30000

              e.url = url
              e.method = method
              e.params = params
              e.statusCode = response.statusCode
              e.statusText = response.statusText
              e.originalError = e
              throw e
      .rename("Api::_doRequest(#{method}, #{url})")

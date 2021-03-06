define [
  'cord!Utils'
  'cord!utils/Future'
  'underscore'
  'postal'
  'cord!AppConfigLoader'
  'eventemitter3'
  'cord!request/errors'
], (Utils, Future, _, postal, AppConfigLoader, EventEmitter, httpErrors) ->

  withResponseFutureExtendFn = ->
    ###
    Special non-closure function which is injected into the promise returned by Api::_doRequest() method.
     It can be used to get lower-level Response instance with helpful response info instead of parsed JSON response body.
     Example: `api.get('getInfo').withResponse().then (response) -> response.statusCode`
    @see Api::send()
    @return {Future<Response>}
    ###
    self = this
    @then -> self.__apiResponse


  class Api extends EventEmitter

    @inject: ['cookie', 'request', 'tabSync', 'logger']

    # Cookie name for auth module name
    @authModuleCookieName: '_api_auth_module'

    fallbackErrors: null

    # Default auth module, check out config.api.defaultAuthModule
    defaultAuthModule: 'OAuth2'

    # Default retry parameters
    retryCount: 3
    retryInterval: 200
    retryTimeout: 20000

    constructor: (serviceContainer) ->
      @fallbackErrors = {}
      @serviceContainer = serviceContainer


    init: ->
      # заберем настройки для fallbackErrors
      AppConfigLoader.ready().done (appConfig) =>
        @fallbackErrors = appConfig.fallbackApiErrors


    configure: (config, createNewAuth = true) ->
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
        cookiePrefix: null

      @options = _.extend(defaultOptions, @options, config)
      @defaultAuthModule = @options.defaultAuthModule if @options.defaultAuthModule

      @setupAuthModule(createNewAuth)


    getBackendHost: ->
      ###
      Returns currently used api backend host
      ###
      @options.host


    setupAuthModule: (createNewAuth = true) ->
      ###
      Initializer. Should be called after injecting @inject services
      ###
      if @options.forcedAuthModule
        module = @options.forcedAuthModule
      else if @cookie.get(Api.authModuleCookieName)
        module = @cookie.get(Api.authModuleCookieName)
      else
        module = @defaultAuthModule

      @setAuthModule(module, createNewAuth).catch (e) =>
        _console.error(e)
        module = @defaultAuthModule
        if not module
          throw new Error('Api unable to determine auth module name. Please check out config.api.defaultAuthModule')

        @setAuthModule(module)


    setAuthModule: (modulePath, createNewAuth = true) ->
      ###
      Sets or replaces current authentication module.
      The method can be called consequently, it guarantees, that @authPromise will be resolved with latest module
      @param {String} modulePath - absolute or relative to core/auth path to Auth module
      @return {Future[<auth module instance>]}
      ###
      return Future.rejected('Api::setAuthModule modulePath needed')  if not modulePath

      originalModule = modulePath
      modulePath = "/cord/core/auth/#{ modulePath }"  if modulePath.charAt(0) != '/'

      # Ignore double call of this method with same module
      return @authPromise if modulePath == @lastModulePath and @authPromise and (not @authPromise.completed() or not createNewAuth)

      @logger.log "Loading auth module: #{modulePath}"  if global.config.debug.oauth

      localAuthPromise = Future.single("Auth module promise: #{modulePath}")
      @lastModulePath = modulePath # To check that we resolve @authPromise with the latest modulePath

      Future.require('cord!' + modulePath).then (Module) =>
        # this is workaround for requirejs-on-serverside bug which doesn't throw an error when requested file doesn't exist
        throw new Error("Failed to load auth module #{modulePath}!")  if not Module
        if @lastModulePath == modulePath # To check that we resolve @authPromise with the latest modulePath
          @cookie.set(Api.authModuleCookieName, originalModule, expires: 365)
          module = new Module(@options[Module.configKey], @cookie, @request, @tabSync, @options.cookiePrefix)
          localAuthPromise.resolve(module)
          # bypass module event
          module.on('auth.available', => @emit('auth.available'))
          module

      .catch (error) =>
        if @lastModulePath == modulePath # To check that we resolve @authPromise with the latest modulePath
          localAuthPromise.reject(error)
        @logger.error("Unable to load auth module: #{modulePath} with error", error)

      @authPromise.when(localAuthPromise)  if @authPromise and not @authPromise.completed()
      @authPromise = localAuthPromise


    authTokensAvailable: ->
      ###
      Checks if there are stored auth tokens that can be used for authenticated request.
      @return Future{Boolean}
      ###
      if not @authPromise
        @logger.warn('Api::authTokensAvailable authPromise does not exists. Call setAuthModule before use.')
        Future.resolved(false)
      else
        @authPromise.then (authModule) ->
          authModule.isAuthAvailable()
        .catch (e) ->
          @logger.warn('authTokensAvailable failed, because of:', e)
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
      @return {Future} resolves when auth succeeded, fails otherwise
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
        authModule.clearAuth().then =>
          authModule.tryToAuth().catch (e) =>
            if @options.authenticateUserCallback()
              @authTokensReady()
            else
              Future.rejected(e)


    get: (url, params, callback) ->
      @send 'get', url, params, callback


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

      if validatedArgs.callback
        console.trace 'DEPRECATION WARNING: callback-style Api::send result is deprecated, use promise-style result instead!', validatedArgs.callback

      requestPromise = (
        if validatedArgs.params.noAuthTokens
          url = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{validatedArgs.url}"
          @_doRequest(validatedArgs.method, url, validatedArgs.params, validatedArgs.params.retryCount ? @retryCount)
        else
          @_prepareRequestArgs(validatedArgs).then (preparedArgs) =>
            @_doRequest(preparedArgs.method, preparedArgs.url, preparedArgs.params, preparedArgs.params.retryCount ? @retryCount)
      ).then (response) ->
        # hack: injecting response instance into the returning promise to support injected `withResponse` method
        requestPromise.__apiResponse = response
        # default behaviour is to return parsed JSON body
        if Array.isArray(response.body) and response.body.length == 1
          response.body.__canHaveLengthOne = true
        response.body


      # extending returned promise with special `withResponse` method
      requestPromise.withResponse = withResponseFutureExtendFn

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
        @logger.warn("Auth failed:", e)
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


    _doRequest: (method, url, params, retryCount = @retryCount, retryTill = Date.now() + @retryTimeout) ->
      ###
      Performs actual HTTP request with the given params.
      Smartly handles different edge cases (i.e. auth errors) - tries to fix them and repeats recursively.
      @param {String} method HTTP method - get, post, put, delete
      @param {String} url Fully-qualified URL
      @param {Object} params Request params according to the curly spec
      @param {Int} retryCount Maximum number of retries before give up in case of errors (where applicable)
      @param {Int} retryTill When we should stop trying to make a request in format of Date.now(). 0 for no timeout
      @return {Future<Response>} response object like in curly
      ###
      requestParams = _.clone(params)
      delete requestParams.originalArgs
      @authPromise.then (authModule) =>
        @request[method](url, requestParams).then (response) =>
          # If backend want to change host, override it
          # Event should be handler by api service factory
          if response.headers.has('X-Target-Host') and response.headers.get('X-Target-Host') != '127.0.0.1'
            @emit('target.host.changed', response.headers.get('X-Target-Host'))
          response

        .catchIf httpErrors.Network, (e) =>
          # In case of network error, we'll try to reconnect again
          if retryCount > 0 and method == 'get' and (retryTill == 0 or retryTill >= Date.now())
            @logger.warn "WARNING: request to #{url} failed because of network error #{e}. Retrying after #{@retryInterval/1000}s..."

            Future.timeout(@retryInterval).then =>
              @_doRequest(method, url, params, retryCount - 1, retryTill)
          else
            throw e

        .catchIf httpErrors.InvalidResponse, (e) =>
          # Handle invalid server response. i.e. 401, 403, 500 and etc..
          # We can not handle here network errors, so, it will throws to external handlers
          response = e.response
          isAuthFailed = authModule.isAuthFailed(response.body)
          # if auth failed normally, we try to resuurect auth and try again
          if isAuthFailed and not params.skipAuth and retryCount > 0 and ( retryTill == 0 or retryTill >= Date.now() )
            # need to use originalArgs here to workaround situation when API host is changed during request
            @_prepareRequestArgs(params.originalArgs).then (preparedArgs) =>
              @_doRequest(preparedArgs.method, preparedArgs.url, preparedArgs.params, retryCount - 1, retryTill)

          # if request failed in other cases
          else
            message = response.body?._message ? response.body?.message ? response.statusText

            # Post could make duplicates
            if method == 'get' and retryCount > 0 and ( retryTill == 0 or retryTill >= Date.now() )
              @logger.warn "WARNING: request to #{url} failed due to invalid response. #{JSON.stringify(response)} Retrying after #{@retryInterval/1000}s..."

              Future.timeout(@retryInterval).then =>
                @_doRequest(method, url, params, retryCount - 1, retryTill)
            else
              # handle API errors fallback behaviour if configured
              errorCode = response.body?._code ? response.statusCode
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
                message = 'Error ' + (if response.statusCode != undefined then (' ' + response.statusCode)) + ': ' + message
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
              throw e
      .rename("Api::_doRequest(#{method}, #{url})")


    clearAuth: ->
      Future.try =>
        @authPromise?.then (authModule) ->
          authModule.clearAuth()
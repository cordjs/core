define [
  'cord!Utils'
  'cord!utils/Future'
  'underscore'
  'postal'
  'cord!isBrowser'
  'cord!AppConfigLoader'
  'eventemitter3'
], (Utils, Future, _, postal, isBrowser, AppConfigLoader, EventEmitter) ->


  class Api extends EventEmitter

    @inject: ['cookie', 'oauth2', 'request']

    accessToken: false
    refreshToken: false

    fallbackErrors: null


    constructor: (serviceContainer, options) ->
      @fallbackErrors = {}
      @updateOptions(options)

      # заберем настройки для fallbackErrors
      AppConfigLoader.ready().done (appConfig) =>
        @fallbackErrors = appConfig.fallbackApiErrors

      @serviceContainer = serviceContainer
      @accessToken = ''
      @restoreToken = ''


    updateOptions: (options) ->
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

      @options = _.extend(defaultOptions, options)

      # если в конфиге у нас заданы параметры автовхода, то надо логиниться по ним
      if @options.autoLogin? and @options.autoPassword?
        @options.authenticateUserCallback = =>
          @getTokensByUsernamePassword @options.autoLogin, @options.autoPassword

      return


    getScope: ->
      ###
      Generates random scope for every browser (client) to prevent access-token auto-deletion when someone logging in
       from different computers (browsers) (e.g. at work and at home)
      @return {String}
      ###
      if not @scope
        @scope = Math.round(Math.random() * 10000000)
      @scope


    storeTokens: (accessToken, refreshToken) ->
      ###
      Stores oauth tokens to cookies to be available after page refresh.
      @param {String} accessToken
      @param {String} refreshToken
      ###
      return if @accessToken == accessToken and @refreshToken == refreshToken

      @accessToken = accessToken
      @refreshToken = refreshToken
      @scope = @getScope()

      @cookie.set('accessToken', @accessToken, expires: 15)
      @cookie.set('refreshToken', @refreshToken, expires: 15)
      @cookie.set('oauthScope', @scope, expires: 15)

      _console.log "Store tokens: #{accessToken}, #{refreshToken}"  if global.config.debug.oauth2

      return


    authTokensAvailable: ->
      ###
      Checks if there are stored auth tokens that can be used for authenticated request.
      @return {Boolean}
      ###
      @restoreTokens()
      !!(@accessToken and @refreshToken)


    authTokensReady: ->
      ###
      Returns a promise that completes when auth tokens are available and authenticated requests can be done
      @return {Future[undefined]}
      ###
      if @authTokensAvailable()
        Future.resolved()
      else
        result = Future.single('authTokensReady')
        @once 'auth.tokens.ready', =>
          result.when(@authTokensReady()) # recursively checking if auth tokens actually valid
        result


    restoreTokens: ->
      ###
      Loads saved tokens from cookies
      ###
      if not (@accessToken and @refreshToken)
        @accessToken  = @cookie.get('accessToken')
        @refreshToken = @cookie.get('refreshToken')
        @scope        = @cookie.get('oauthScope')
      return


    getCurrentAccessToken: ->
      ###
      Gives public access to the current access token.
      @return {String}
      ###
      @restoreTokens()
      @accessToken


    _invalidateAccessToken: ->
      @accessToken = null
      @cookie.set('accessToken')
      return


    getTokensByUsernamePassword: (username, password, cb) ->
      ###
      Requests and returns OAuth2 tokens by username and password.
      @param {String} username
      @param {String} password
      @param (deprecated, optional){Function} cb old-style callback
      @return {Future[Tuple[String, String]]} [access token, refresh token]
      ###
      result = Future.single('getTokensByUsernamePassword')
      @oauth2.grantAccessTokenByPassword username, password, @getScope(), (accessToken, refreshToken) =>
        @onAccessTokenGranted(accessToken, refreshToken)
        result.resolve([accessToken, refreshToken])
        cb?(accessToken, refreshToken)
      result


    getTokensByExtensions: (url, params, callback) ->
      @oauth2.grantAccessTokenByExtensions url, params, @getScope(), (accessToken, refreshToken) =>
        @onAccessTokenGranted(accessToken, refreshToken)
        callback?(accessToken, refreshToken)


    onAccessTokenGranted: (accessToken, refreshToken) ->
      @storeTokens(accessToken, refreshToken)
      @emit 'auth.tokens.ready',
        accessToken: accessToken
        refreshToken: refreshToken


    doAuthCodeLoginByPassword: (login, password) ->
      ###
      This one is used for normal Auth2 procedure, not MegaId
      ###
      @oauth2.getAuthCodeByPassword(login, password, @getScope()).name('Api::doAuthCodeLoginByPassword')
        .then (code) =>
          @oauth2.grantAccessTokenByAuhorizationCode(code, @getScope())
        .then (accessToken, refreshToken, code) =>
          @onAccessTokenGranted(accessToken, refreshToken)
          code


    doAuthCodeLoginWithoutPassword: ->
      ###
      This one is used for normal Auth2 procedure, not MegaId
      ###
      @oauth2.getAuthCodeWithoutPassword(@getScope()).name('Api::doAuthCodeLoginWithoutPassword')
        .then (code) =>
          @oauth2.grantAccessTokenByAuhorizationCode(code)
        .then (accessToken, refreshToken, code) =>
          @onAccessTokenGranted(accessToken, refreshToken)
          code


    getAccessTokenByMegaId: ->
      ###
      This one is used exclusevely for MegaId via backend (for security reasons)
      ###
      @oauth2.getAuthCodeWithoutPassword(@getScope()).name('Api::getAccessTokenByMegaId')
        .then (code) =>
          @oauth2.grantAccessTokenByMegaId(code, @getScope())
        .then (accessToken, refreshToken, code) =>
          @onAccessTokenGranted(accessToken, refreshToken)
          code


    getAccessTokenByInviteCode: (inviteCode) ->
      @oauth2.getAuthCodeWithoutPassword(@getScope()).name('Api::getAccessTokenByMegaId')
        .then (code) =>
          @oauth2.grantAccessTokenByInviteCode(inviteCode, code, @getScope())
        .then (accessToken, refreshToken, code) =>
          @onAccessTokenGranted(accessToken, refreshToken)
          code


    authenticateUser: ->
      ###
      Initiates pluggable via authenticateUserCallback-option authentication of the user and waits for the global
       event with the auth-tokens which must be triggered by that procedure.
      Callback-function-option authenticateUserCallback must return boolean 'true' if authentication can be performed
       without user interaction, or boolean 'false' if user interaction is required (for example, login form submission)
       and authentication wait time is not determined.
      @return {Future[Tuple[String, String]]} access- and refresh-tokens.
      ###
      result = Future.single('Api::authenticateUser')

      # Clear Cookies
      @cookie.set('accessToken')
      @cookie.set('refreshToken')
      @cookie.set('oauthScope')
      if @options.megaplanId?.useMegaplanId
        # Try to accuire tokens via MegaId
        @getAccessTokenByMegaId()
          .catch (e) =>
            # Whoops, needed login via Megaplan Start, on client we redirect to start, on server to special auth page
            @options.authenticateUserCallback()

      else if @options.authenticateUserCallback() # true means possibility of auto-login without user-interaction
        @once 'auth.tokens.ready', (tokens) ->
          result.resolve([tokens.accessToken, tokens.refreshToken])
      else
        result.reject(new Error('Auto-login is not available!'))

      result


    getTokensByRefreshToken: ->
      ###
      Refreshes auth tokens pair by the existing refresh token.
      @return {Future[Tuple[String, String]]} new access and refresh tokens
      ###
      @oauth2.grantAccessTokenByRefreshToken(@refreshToken, @getScope()).spread (grantedAccessToken, grantedRefreshToken) =>
        if grantedAccessToken and grantedRefreshToken
          @storeTokens grantedAccessToken, grantedRefreshToken
          [[grantedAccessToken, grantedRefreshToken]]
        else
          throw new Error('Failed to get auth token by refresh token: refresh token is outdated!')


    _getTokensByAllMeans: ->
      ###
      Tries to get auth tokens from different sources in this order:
      1. Local cache (cookies)
      2. Get new tokens by refresh token
      3. Initiate pluggable user authentication process.
      @return {Future[Tuple[String, String]]} access and refresh tokens
      ###
      @restoreTokens()
      if not @accessToken
        if @refreshToken
          @getTokensByRefreshToken().catch (err) =>
            @authenticateUser()
        else
          @authenticateUser()
      else
        Future.resolved([@accessToken, @refreshToken])


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

      @_prepareRequestArgs(validatedArgs).then (preparedArgs) =>
        @_doRequest(preparedArgs.method, preparedArgs.url, preparedArgs.params, preparedArgs.params.retryCount ? 5)
      .done (response) ->
        validatedArgs.callback?(response)
      .fail (err) ->
        validatedArgs.callback?(err.response, err)


    _prepareRequestArgs: (args) ->
      ###
      Prepares request params for the _doRequest method, according to the current API settings.
      @param {Object} args
      @return {Future[Object]}
      ###
      @_injectAuthParams(args.url, args.params).spread (url, params) =>
        method: args.method
        url:    "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{url}"
        params: _.extend({ originalArgs: args }, @options.params, params)


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
      resultPromise = Future.single("Api::_doRequest(#{method}, #{url})")
      requestParams = _.clone(params)
      delete requestParams.originalArgs
      @request[method] url, requestParams, (response, error) =>
        Future.try =>
          # if auth failed
          if not params.skipAuth and
             (response?.error == 'invalid_grant' or response?.error == 'invalid_request') and
             retryCount > 0

            @_invalidateAccessToken()
            # try to get new access token using refresh token and retry request
            # need to use originalArgs here to workaround situation when API host is changed during request
            @_prepareRequestArgs(params.originalArgs).then (preparedArgs) =>
              @_doRequest(preparedArgs.method, preparedArgs.url, preparedArgs.params, retryCount - 1)

          # if request failed in other cases
          else if error
            if error.statusCode or error.message
              message = error.message if error.message
              message = error.statusText if error.statusText

              # Post could make duplicates
              if method == 'get' and params.reconnect and
                 (not error.statusCode or error.statusCode == 500) and
                 retryCount > 0

                _console.warn "WARNING: request to #{url} failed! Retrying after 0.5s..."

                Future.timeout(500).then =>
                  @_doRequest(method, url, params, retryCount - 1)

              else
                # handle API errors fallback behaviour if configured
                errorCode = response?._code ? error.statusCode
                if errorCode? and @fallbackErrors and @fallbackErrors[errorCode]
                  fallbackInfo = _.clone(@fallbackErrors[errorCode])
                  fallbackInfo.params = _.clone(fallbackInfo.params)
                  # если есть доппараметры у ошибки - добавим их
                  if response._params?
                    fallbackInfo.params.contentParams =
                      if not fallbackInfo.params.contentParams?
                        {}
                      else
                        _.clone(fallbackInfo.params.contentParams)
                    fallbackInfo.params.contentParams['params'] = response._params

                  @serviceContainer.get('fallback').fallback(fallbackInfo.widget, fallbackInfo.params)

                # otherwise just notify the user
                else
                  message = 'Ошибка ' + (if error.statusCode != undefined then (' ' + error.statusCode)) + ': ' + message
                  postal.publish 'error.notify.publish',
                    link: ''
                    message: message
                    error: true
                    timeOut: 30000

            e = new Error(error.message)
            e.url = url
            e.method = method
            e.params = params
            e.statusCode = error.statusCode
            e.statusText = error.statusText
            e.originalError = error
            e.response = response
            throw e

          # if everything is all right
          else
            response

        .link(resultPromise)

      resultPromise


    _injectAuthParams: (url, params) ->
      ###
      Adds to the given URL and params oauth access token if needed and returns them.
      @param {String} url
      @param {Object} params
      @return {Future[Tuple[String, Object]]}
      ###
      if params.noAuthTokens
        Future.resolved([url, params])
      else
        @restoreTokens()
        if params.skipAuth
          url += ( if url.lastIndexOf('?') == -1 then '?' else '&' ) + "access_token=#{@accessToken}"
          Future.resolved([url, params])
        else
          @_getTokensByAllMeans().spread (accessToken) ->
            url += ( if url.lastIndexOf('?') == -1 then '?' else '&' ) + "access_token=#{accessToken}"
            [[url, params]]

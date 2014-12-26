define [
  'underscore'
  'cord!isBrowser'
  'cord!utils/Future'
], (_, isBrowser, Future) ->

  class OAuth2

    @inject: ['request', 'config']

    constructor: (options) ->
      @deferredRefreshTokenCallbacks = []
      @refreshTokenRequested = false

      defaultOptions =
        clientId: ''
        secretKey: ''
        endpoints:
          authorize: '/oauth/authorize'
          accessToken: '/oauth/access_token'
      @options = _.extend defaultOptions, options


    grantAccessTokenByAuhorizationCode: (code) ->
      ###
      Получает токены по коду авторизации, ранее выданному авторизационным сервером
      ###
      debugger
      promise = Future.single('OAuth2::grantAccessTokenByAuthorizationCode promise')
      params =
        grant_type: 'authorization_code'
        code: code
        client_id: @options.clientId
        client_secret: '#{client_secret}'
        format: 'json'
        redirect_uri: @options.endpoints.redirectUri

      requestUrl = "#{@options.xdrs.protocol}://#{@options.xdrs.host}#{@options.xdrs.urlPrefix}#{@options.endpoints.accessToken}"

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          promise.reject(new Error('No response from authorization server'))
      promise


    ## Получение токена по grant_type = password (логин и пароль)
    grantAccessTokenByPassword: (user, password, scope, callback) ->
      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @options.clientId
        scope: scope
        json: true

      @request.get @options.endpoints.accessToken, params, (result) =>
        if result
          callback result.access_token, result.refresh_token
        else
          callback null, null


    ## Получение токена по grant_type = extension (например, одноразовый ключ)
    grantAccessTokenByExtensions: (url, params, scope, callback) ->
      requestParams =
        grant_type: url
        client_id: @options.clientId
        scope: scope
        json: true

      requestParams = _.extend params, requestParams

      @request.get @options.endpoints.accessToken, requestParams, (result) =>
        if result
          callback result.access_token, result.refresh_token
        else
          callback null, null


    clear: ->
      @deferredRefreshTokenCallbacks = []


    ## Получение токена по grant_type = refresh_token (токен обновления)
    grantAccessTokenByRefreshToken: (refreshToken, scope, callback) =>
      @deferredRefreshTokenCallbacks.push callback if callback

      params =
        grant_type: 'refresh_token'
        refresh_token: refreshToken
        client_id: @options.clientId
        scope: scope

      if @refreshTokenRequested
        _console.log "========================================================================"
        _console.log "Refresh token already requested"
        _console.log "========================================================================"

      return if @refreshTokenRequested or @deferredRefreshTokenCallbacks.length == 0

      @refreshTokenRequested = true

      @request.get @options.endpoints.accessToken, params, (result) =>
        # Если порвалась связь, то не считаем протухшим рефреш токен
        @refreshTokenRequested = false

        if result && (result.access_token || result.error)
          # Рефреш токен протух
          callbackResult = true
          for callback in @deferredRefreshTokenCallbacks
            #Protection from multiple redirections
            callbackResult &= callback result.access_token, result.refresh_token if callbackResult

          @deferredRefreshTokenCallbacks = []

        else
          _console.log 'Cannot refresh token (('
          setTimeout =>
            _console.log 'Recall refresh token'
            @grantAccessTokenByRefreshToken refreshToken
          , 500


    getAuthCodeWithoutPassword: ->
      ###
      Try to acquire auth Code. Succeeds only if user has been already logged in.
      Oauth2 server uses it's cookies to identify user
      ###
      promise = Future.single('Api::getAuthCodeWithoutPassword promise')
      if not isBrowser
        promise.reject(new Error('It is only possible to get auth code at client side'))
      else
        params =
          response_type: 'code'
          client_id: @config.oauth2.clientId
          format: 'json'
          xhrOptions:
            withCredentials: true

        requestUrl = @config.oauth2.endpoints.authCodeWithoutLogin
        @request.get requestUrl, params, (response, error) ->
          if response.code
            promise.resolve(response.code)
          else
            promise.reject(new Error('No auth code recieved. Response: ' + JSON.stringify(response) + JSON.stringify(error)))
      promise


    getAuthCodeByPassword: (login, password) ->
      debugger
      promise = Future.single('Api::getAuthCodeByPassword promise')
      if !isBrowser
        promise.reject(new Error('It is only possible to get auth code at client side'))
      else
        params =
          response_type: 'code'
          client_id: @config.oauth2.clientId
          login: login
          password: password
          format: 'json'
          xhrOptions:
            withCredentials: true

        requestUrl = @config.oauth2.endpoints.authCode
        @request.get requestUrl, params, (response, error) ->
          if response and response.code
            promise.resolve(response.code)
          else
            promise.reject(new Error('No auth code recieved. Response:'+ JSON.stringify(response) + JSON.stringify(error)))
      promise

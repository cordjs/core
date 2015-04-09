define [
  'underscore'
], (_) ->

  class OAuth2

    constructor: (serviceContainer, options) ->
      @deferredRefreshTokenCallbacks = []
      @refreshTokenRequested = false

      defaultOptions =
        clientId: ''
        secretKey: ''
        endpoints:
          authorize: '/oauth/authorize'
          accessToken: '/oauth/access_token'
      @options = _.extend  defaultOptions, options
      @serviceContainer = serviceContainer


    grantAccessTokenByAuhorizationCode: (code, callback) =>
      ###
      Получает токены по коду авторизации, ранее выданному авторизационным сервером
      ###
      params =
        grant_type: 'authorization_code'
        code: code
        client_id: @options.clientId
        client_secret: @options.secretKey
        format: 'json'
        redirect_uri: @options.endpoints.redirectUri

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, params, (result) =>
          if result
            callback result.access_token, result.refresh_token
          else
            callback null, null


    ## Получение токена по grant_type = password (логин и пароль)
    grantAccessTokenByPassword: (user, password, scope, callback) =>
      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @options.clientId
        scope: scope
        json: true

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, params, (result) =>
          if result
            callback result.access_token, result.refresh_token
          else
            callback null, null


    ## Получение токена по grant_type = extension (например, одноразовый ключ)
    grantAccessTokenByExtensions: (url, params, scope, callback) =>
      requestParams =
        grant_type: url
        client_id: @options.clientId
        scope: scope
        json: true

      requestParams = _.extend params, requestParams

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, requestParams, (result) =>
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

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, params, (result) =>
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


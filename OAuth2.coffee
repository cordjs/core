define [
  'underscore'
], (_) ->

  class OAuth2

    deferredRefreshTokenCallbacks: []
    refreshTokenRequested: false

    constructor: (serviceContainer, options)->
      defaultOptions =
        clientId: ''
        secretKey: ''
        endpoints:
          authorize: '/oauth/authorize'
          accessToken: '/oauth/access_token'
      @options = _.extend  defaultOptions, options
      @serviceContainer = serviceContainer


    ## Получение токена по grant_type = password (логин и пароль)
    grantAccessTokenByPassword: (user, password, callback) =>
      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @options.clientId
        json: true

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, params, (result) =>
          callback result.access_token, result.refresh_token


    ## Получение токена по grant_type = refresh_token (токен обновления)
    grantAccessTokenByRefreshToken: (refreshToken, callback) =>
      @deferredRefreshTokenCallbacks.push callback if callback

      params =
        grant_type: 'refresh_token'
        refresh_token: refreshToken
        client_id: @options.clientId

      if @refreshTokenRequested
        console.log "========================================================================"
        console.log "Refresh token already requested"
        console.log "========================================================================"

      return if @refreshTokenRequested or @deferredRefreshTokenCallbacks.length == 0

      @refreshTokenRequested = true

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, params, (result) =>
          # Если порвалась связь, то не считаем протухшим рефреш токен
          @refreshTokenRequested = false

          if result && (result.access_token || result.error)
            # Рефреш токен протух
            for callback in @deferredRefreshTokenCallbacks
              callback result.access_token, result.refresh_token

            @deferredRefreshTokenCallbacks = []

          else
            console.log 'Cannot refresh token (('
            setTimeout () =>
              console.log 'Recall refresh token'
              @grantAccessTokenByRefreshToken refreshToken
            , 500


define [
  'cord!ServiceContainer'
  'underscore'
], (serviceContainer, _) ->

  class OAuth2

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
      params =
        grant_type: 'refresh_token'
        refresh_token: refreshToken
        client_id: @options.clientId

      @serviceContainer.eval 'request', (request) =>
        request.get @options.endpoints.accessToken, params, (result) =>
          callback result.access_token, result.refresh_token
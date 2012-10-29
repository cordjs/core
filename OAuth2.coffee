define [
  'cord!Request'
  'underscore'
], (Request, _) ->

  ###
  #
  # OAuth авторизация
  #
  ###
  class OAuth2
    constructor: (options)->
      defaultOptions =
        clientId: ''
        secretKey: ''
        endpoints:
          authorize: '/oauth/authorize'
          accessToken: '/oauth/access_token'

      @options = _.extend  defaultOptions, options
      @request = new Request()

    ## Получение токена по grant_type = password (логин и пароль)
    grantAccessTokenByPassword: (user, password, callback) =>
      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @options.clientId
        json: true

      @request.get @options.endpoints.accessToken, params, (result) =>
        callback result.access_token, result.refresh_token

    ## Получение токена по grant_type = refresh_token (токен обновления)
    grantAccessTokenByRefreshToken: (refreshToken, callback) =>
      params =
        grant_type: 'refresh_token'
        refresh_token: refreshToken
        client_id: @options.clientId

      @request.get @options.endpoints.accessToken, params, (result) =>
        callback result.access_token, result.refresh_token
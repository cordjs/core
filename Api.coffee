define [
  'cord!Request'
  'cord!Cookie'
  'cord!OAuth2'
  'cord!Utils'
  'underscore'
], (Request, Cookie, OAuth2, Utils, _) ->


  class Api

    constructor: (options) ->
      ### Дефолтные настройки ###
      defaultOptions =
        protocol: 'http'
        host: 'localhost'
        urlPrefix: ''
        params: []
        oauth2:
          clientId: ''
          secretKey: ''
        http:
          request: null
          response: null
        getUserPasswordCallback: (callback) -> callback 'fakeUser', 'fakePassword'

      @options = _.extend defaultOptions, options
      @request = new Request()
      @oauth = new OAuth2 @options.oauth2

      @accessToken = ''
      @restoreToken = ''


    storeTokens: (accessToken, refreshToken) =>
      cookie = new Cookie @options.http.request, @options.http.response
      cookie.set 'accessToken', accessToken
      cookie.set 'refreshToken', refreshToken

      console.log "Store tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug?.oauth2


    restoreTokens: =>
      cookie = new Cookie @options.http.request, @options.http.response
      @accessToken = cookie.get 'accessToken'
      @refreshToken = cookie.get 'refreshToken'

      console.log "Restore tokens: #{@accessToken}, #{@refreshToken}" if global.CONFIG.debug?.oauth2


    get: =>
      args = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      @restoreTokens()

      processRequest = (accessToken) =>
        requestUrl = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{args.url}"
        requestParams = _.extend @options.params, args.params
        requestParams.access_token = accessToken
        @request.get requestUrl, requestParams, args.callback

      if not @accessToken
        @options.getUserPasswordCallback (username, password) =>
          @oauth.grantAccessTokenByPassword username, password, (accessToken, refreshToken) =>
            @storeTokens(accessToken, refreshToken)

            processRequest(accessToken)
      else
        processRequest(@accessToken)
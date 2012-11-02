define [
  'cord!Utils'
  'underscore'
], (Utils, _) ->


  class Api

    constructor: (serviceContainer, options) ->
      ### Дефолтные настройки ###
      defaultOptions =
        protocol: 'http'
        host: 'localhost'
        urlPrefix: ''
        params: []
        getUserPasswordCallback: (callback) -> callback 'jedi', 'jedi'
      @options = _.extend defaultOptions, options

      @serviceContainer = serviceContainer
      @accessToken = ''
      @restoreToken = ''


    storeTokens: (accessToken, refreshToken, callback) ->
      @serviceContainer.eval 'cookie', (cookie) =>
        cookie.set 'accessToken', accessToken
        cookie.set 'refreshToken', refreshToken

        console.log "Store tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug?.oauth2

        callback accessToken, refreshToken


    restoreTokens: (callback) ->
      @serviceContainer.eval 'cookie', (cookie) =>
        accessToken = cookie.get 'accessToken'
        refreshToken = cookie.get 'refreshToken'

        console.log "Restore tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug?.oauth2

        callback accessToken, refreshToken

    getTokensByUsernamePassword: (username, password, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByPassword username, password, (accessToken, refreshToken) =>
          @storeTokens accessToken, refreshToken, callback

    get: ->
      args = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      processRequest = (accessToken) =>
        requestUrl = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{args.url}"
        requestParams = _.extend @options.params, args.params
        requestParams.access_token = accessToken

        @serviceContainer.eval 'request', (request) ->
          request.get requestUrl, requestParams, args.callback

      @restoreTokens (accessToken, refreshToken) =>
        if not accessToken
          @options.getUserPasswordCallback (username, password) =>
            @getTokensByUsernamePassword (accessToken, refreshToken) =>
              processRequest(accessToken)
        else
          processRequest(accessToken)

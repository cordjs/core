define [
  'cord!Utils'
  'underscore'
], (Utils, _) ->


  class Api

    constructor: (serviceContainer, options) ->
      ### Дефолтные настройки ###
      defaultOptions =
        protocol: 'http'
        host: 'megaplan.megaplan.ru'
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

    getTokensByRefreshToken: (refreshToken, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByRefreshToken refreshToken, (accessToken, refreshToken) =>
          @storeTokens accessToken, refreshToken, callback

    get: (url, params, callback) ->
      @send 'get', url, params, callback

    post: (url, params, callback) ->
      @send 'post', url, params, callback

    put: (url, params, callback) ->
      @send 'put', url, params, callback

    del: (url, params, callback) ->
      @send 'del', url, params, callback

    send: ->
      method = arguments[0];
      args = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      console.log args
      processRequest = (accessToken, refreshToken) =>
        if not accessToken
          @options.getUserPasswordCallback (username, password) =>
            @getTokensByUsernamePassword username, password, (accessToken, refreshToken) =>
              processRequest accessToken, refreshToken
          false

        requestUrl = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{args.url}"
        defaultParams = _.clone @options.params
        requestParams = _.extend defaultParams, args.params
        requestParams.access_token = accessToken

        @serviceContainer.eval 'request', (request) =>
          request[method] requestUrl, requestParams, (response) =>
            if response?.error?
              if response.error == 'invalid_grant' and refreshToken
                @getTokensByRefreshToken refreshToken, processRequest
              else
                @options.getUserPasswordCallback (username, password) =>
                  @getTokensByUsernamePassword username, password, (accessToken, refreshToken) =>
                    processRequest accessToken, refreshToken
            else
              args.callback response

      @restoreTokens (accessToken, refreshToken) =>
        if not accessToken
          @options.getUserPasswordCallback (username, password) =>
            @getTokensByUsernamePassword username, password, (accessToken, refreshToken) =>
              processRequest accessToken, refreshToken
        else
          processRequest accessToken, refreshToken

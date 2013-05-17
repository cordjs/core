define [
  'cord!Utils'
  'underscore'
  'postal'
], (Utils, _, postal) ->


  class Api

    accessToken: false
    refreshToken: false

    constructor: (serviceContainer, options) ->
      ### Дефолтные настройки ###
      defaultOptions =
        protocol: 'http'
        host: 'megaplan.megaplan'
        urlPrefix: ''
        params: {}
        getUserPasswordCallback: (callback) -> callback '', ''
      @options = _.extend defaultOptions, options

      @serviceContainer = serviceContainer
      @accessToken = ''
      @restoreToken = ''


    storeTokens: (accessToken, refreshToken, callback) ->
      # Кеширование токенов
      @accessToken = accessToken
      @refreshToken = refreshToken

      @serviceContainer.eval 'cookie', (cookie) =>
        cookie.set 'accessToken', @accessToken
        cookie.set 'refreshToken', @refreshToken,
          expires: 14

        console.log "Store tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug?.oauth2

        callback @accessToken, @refreshToken


    restoreTokens: (callback) ->
      # Возвращаем из локального кеша
      if @accessToken and @refreshToken
        console.log "Restore tokens from local cache: #{@accessToken}, #{@refreshToken}" if global.CONFIG.debug?.oauth2
        callback @accessToken, @refreshToken
      else
        @serviceContainer.eval 'cookie', (cookie) =>
          accessToken = cookie.get 'accessToken'
          refreshToken = cookie.get 'refreshToken'

          @accessToken = accessToken
          @refreshToken = refreshToken

          console.log "Restore tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug.oauth2

          callback @accessToken, @refreshToken


    getTokensByUsernamePassword: (username, password, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByPassword username, password, (accessToken, refreshToken) =>
          @storeTokens accessToken, refreshToken, callback


    getTokensByRefreshToken: (refreshToken, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByRefreshToken refreshToken, (accessToken, refreshToken) =>
          if accessToken and refreshToken
            @storeTokens accessToken, refreshToken, callback
          else
            @options.getUserPasswordCallback (username, password) =>
              @getTokensByUsernamePassword username, password, (accessToken, refreshToken) =>
                callback accessToken, refreshToken


    getTokensByAllMeans: (accessToken, refreshToken, callback) ->
      if not accessToken
        if refreshToken
          @getTokensByRefreshToken refreshToken, (accessToken, refreshToken) =>
            if accessToken
              callback accessToken, refreshToken
            else
              @options.getUserPasswordCallback (username, password) =>
                @getTokensByUsernamePassword username, password, (accessToken, refreshToken) =>
                  callback accessToken, refreshToken
        else
          @options.getUserPasswordCallback (username, password) =>
            @getTokensByUsernamePassword username, password, (accessToken, refreshToken) =>
              callback accessToken, refreshToken
      else
        callback accessToken, refreshToken


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

    send: ->
      method = arguments[0];
      args = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      processRequest = (accessToken, refreshToken) =>
        @getTokensByAllMeans accessToken, refreshToken, (accessToken, refreshToken) =>
          requestUrl = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{args.url}"
          requestUrl += ( if requestUrl.lastIndexOf("?") == -1 then "?" else "&" ) + "access_token=#{accessToken}"
          defaultParams = _.clone @options.params
          requestParams = _.extend defaultParams, args.params
          requestParams.access_token = accessToken

          @serviceContainer.eval 'request', (request) =>
            request[method] requestUrl, requestParams, (response, error) =>
              if (response && response.code)
                message = 'Ошибка ' + response.code + ': ' + response._message
#                  postal.publish 'notify.addMessage', {link:'', message: message, details: response?.message, error: true, timeOut: 30000 }
                console.warn message

              if (error && (error.statusCode || error.message))
                message = error.message if error.message
                message = error.statusText if error.statusText

                message = 'Ошибка' + (if error.statusCode != undefined then (' ' + error.statusCode)) + ': ' + message
#                  postal.publish 'notify.addMessage', {link:'', message: message, error:true, timeOut: 30000 }
                console.warn message

              args.callback response, error if args.callback

      @restoreTokens processRequest

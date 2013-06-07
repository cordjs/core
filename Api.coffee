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
        protocol: 'https'
        host: 'megaplan.megaplan.ru'
        urlPrefix: ''
        params: {}
        getUserPasswordCallback: (callback) ->
          callback '', ''
      @options = _.extend defaultOptions, options

      @serviceContainer = serviceContainer
      @accessToken = ''
      @restoreToken = ''


    getScope: ->
      if @scope
        return @scope
      @scope = Math.round(Math.random()*10000000)
      return @scope

    storeTokens: (accessToken, refreshToken, callback) ->
      # Кеширование токенов

      if @accessToken == accessToken && @refreshToken == refreshToken
        return callback @accessToken, @refreshToken

      @accessToken = accessToken
      @refreshToken = refreshToken
      @scope = @getScope()

      @serviceContainer.eval 'cookie', (cookie) =>
        #Protection from late callback from closed connections.
        #TODO, refactor OAuth module, so dead callback will be deleted
        success = cookie.set 'accessToken', @accessToken
        success &= cookie.set 'refreshToken', @refreshToken,
          expires: 14
        success &= cookie.set 'oauthScope', @getScope(),
          expires: 14

        console.log "Store tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug?.oauth2

        callback @accessToken, @refreshToken if success


    restoreTokens: (callback) ->
      # Возвращаем из локального кеша
      if @accessToken and @refreshToken
        console.log "Restore tokens from local cache: #{@accessToken}, #{@refreshToken}" if global.CONFIG.debug?.oauth2
        callback @accessToken, @refreshToken
      else
        @serviceContainer.eval 'cookie', (cookie) =>
          accessToken = cookie.get 'accessToken'
          refreshToken = cookie.get 'refreshToken'
          scope = cookie.get 'oauthScope'

          @accessToken = accessToken
          @refreshToken = refreshToken
          @scope = scope

          console.log "Restore tokens: #{accessToken}, #{refreshToken}" if global.CONFIG.debug.oauth2

          callback @accessToken, @refreshToken


    getTokensByUsernamePassword: (username, password, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByPassword username, password, @getScope(), (accessToken, refreshToken) =>
          @storeTokens accessToken, refreshToken, callback


    getTokensByRefreshToken: (refreshToken, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByRefreshToken refreshToken, @getScope(), (grantedAccessToken, grantedRefreshToken) =>
          if grantedAccessToken and grantedRefreshToken
            @storeTokens grantedAccessToken, grantedRefreshToken, callback
            return true #continue processing other deferred callbacks in oauth
          else
            @options.getUserPasswordCallback (username, password) =>
              @getTokensByUsernamePassword username, password, (usernameAccessToken, usernameRefreshToken) =>
                callback usernameAccessToken, usernameRefreshToken
            return false #stop processing other deferred callbacks in oauth


    getTokensByAllMeans: (accessToken, refreshToken, callback) ->
      if not accessToken
        if refreshToken
          return @getTokensByRefreshToken refreshToken, callback
        else
          return @options.getUserPasswordCallback (username, password) =>
            @getTokensByUsernamePassword username, password, (usernameAccessToken, usernameRefreshToken) =>
              return callback usernameAccessToken, usernameRefreshToken

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
      method = arguments[0]
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
            doRequest = ()=>
              request[method] requestUrl, requestParams, (response, error) =>
                if response?.error == 'invalid_grant'
                  return processRequest null, refreshToken

                if (response && response.code)
                  message = 'Ошибка ' + response.code + ': ' + response._message
                  postal.publish 'notify.addMessage', {link:'', message: message, details: response?.message, error: true, timeOut: 30000 }

                if (error && (error.statusCode || error.message))
                  message = error.message if error.message
                  message = error.statusText if error.statusText

                  #Post could make duplicates
                  if method != 'post' && requestParams.reconnect != false && (!error.statusCode || error.statusCode == 500) && requestParams.deepCounter < 10
                    requestParams.deepCounter = if ! requestParams.deepCounter then 1 else requestParams.deepCounter + 1
                    console.log requestParams.deepCounter + " Repeat request in 0.5s", requestUrl
                    setTimeout doRequest, 500
                  else
                    message = 'Ошибка' + (if error.statusCode != undefined then (' ' + error.statusCode)) + ': ' + message
                    postal.publish 'notify.addMessage', {link:'', message: message, error:true, timeOut: 30000 }
                    args.callback response, error if args.callback
                else
                  args.callback response, error if args.callback

            doRequest()

      @restoreTokens processRequest

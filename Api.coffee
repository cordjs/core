define [
  'cord!Utils'
  'cord!utils/Future'
  'underscore'
  'postal'
  'cord!isBrowser'
], (Utils, Future, _, postal, isBrowser) ->


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
        authenticateUserCallback: -> false # @see authenticateUser() method
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

        _console.log "Store tokens: #{accessToken}, #{refreshToken}"

        callback @accessToken, @refreshToken if success


    restoreTokens: (callback) ->
      # Возвращаем из локального кеша
      if !isBrowser and @accessToken and @refreshToken
        _console.log "Restore tokens from local cache: #{@accessToken}, #{@refreshToken}" if global.config.debug.oauth2
        callback @accessToken, @refreshToken
      else
        @serviceContainer.eval 'cookie', (cookie) =>
          accessToken = cookie.get 'accessToken'
          refreshToken = cookie.get 'refreshToken'
          scope = cookie.get 'oauthScope'

          @accessToken = accessToken
          @refreshToken = refreshToken
          @scope = scope

          _console.log "Restore tokens: #{accessToken}, #{refreshToken}" if global.config.debug.oauth2
          callback @accessToken, @refreshToken


    getTokensByUsernamePassword: (username, password, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByPassword username, password, @getScope(), (accessToken, refreshToken) =>
          @storeTokens accessToken, refreshToken, callback
          postal.publish 'auth.tokens.ready',
            accessToken: accessToken
            refreshToken: refreshToken


    getTokensByExtensions: (url, params, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByExtensions url, params, @getScope(), (accessToken, refreshToken) =>
          @storeTokens accessToken, refreshToken, callback
          postal.publish 'auth.tokens.ready',
            accessToken: accessToken
            refreshToken: refreshToken


    authenticateUser: ->
      ###
      Initiates pluggable via authenticateUserCallback-option authentication of the user and waits for the global
       event with the auth-tokens which must be triggered by that procedure.
      Callback-function-option authenticateUserCallback must return boolean 'true' if it's supposed to trigger
       'auth.tokens.ready' event eventually, or boolean 'false' if it's not (for example, there will be some kind
       of page refresh and callback is not applicable.
      @return Future(String, String) - eventually completed with access- and refresh-tokens.
      ###
      result = Future.single()
      if @options.authenticateUserCallback()
        subscription = postal.subscribe
          topic: 'auth.tokens.ready'
          callback: (tokens) =>
            subscription.unsubscribe()
            result.resolve(tokens.accessToken, tokens.refreshToken)
      else
        result.reject('Callback is not applicable in this case.')
      result


    getTokensByRefreshToken: (refreshToken, callback) ->
      @serviceContainer.eval 'oauth2', (oauth2) =>
        oauth2.grantAccessTokenByRefreshToken refreshToken, @getScope(), (grantedAccessToken, grantedRefreshToken) =>
          if grantedAccessToken and grantedRefreshToken
            @storeTokens grantedAccessToken, grantedRefreshToken, callback
            return true #continue processing other deferred callbacks in oauth
          else
            #in case of fail dont call callback - it wont be able to solve the problem,
            #but might run into everlasting loop
            @authenticateUser()
            return false #stop processing other deferred callbacks in oauth


    getTokensByAllMeans: (accessToken, refreshToken, callback) ->
      if not accessToken
        if refreshToken
          @getTokensByRefreshToken refreshToken, callback
        else
          #in case of fail dont call callback - it wont be able to solve the problem,
          #but might run into everlasting loop
          @authenticateUser()
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
      method = arguments[0]
      args = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      noAuthTokens = args.params and args.params.noAuthTokens == true

      processRequest = (accessToken, refreshToken) =>
        requestUrl = "#{@options.protocol}://#{@options.host}/#{@options.urlPrefix}#{args.url}"
        defaultParams = _.clone @options.params
        requestParams = _.extend defaultParams, args.params

        @serviceContainer.eval 'request', (request) =>
          doRequest = =>
            request[method] requestUrl, requestParams, (response, error) =>
              if response?.error == 'invalid_grant' || response?.error == 'invalid_request'
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
                  _console.log requestParams.deepCounter + " Repeat request in 0.5s", requestUrl
                  setTimeout doRequest, 500
                else
                  message = 'Ошибка' + (if error.statusCode != undefined then (' ' + error.statusCode)) + ': ' + message
                  postal.publish 'notify.addMessage', {link:'', message: message, error:true, timeOut: 30000 }
                  args.callback response, error if args.callback
              else
                args.callback response, error if args.callback

          if noAuthTokens
            doRequest()
          else
            @getTokensByAllMeans accessToken, refreshToken, (accessToken, refreshToken) =>
              requestUrl += ( if requestUrl.lastIndexOf("?") == -1 then "?" else "&" ) + "access_token=#{accessToken}"
              requestParams.access_token = accessToken

              doRequest()

      if noAuthTokens
        processRequest()
      else
        @restoreTokens processRequest

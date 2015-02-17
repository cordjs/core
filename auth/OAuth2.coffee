define [
  'underscore'
  'cord!isBrowser'
  'cord!utils/Future'
  'cord!errors'
  'eventemitter3'
], (_, isBrowser, Future, errors, EventEmitter) ->

  class OAuth2 extends EventEmitter
 
    ###
    OAuth2 auth module
    required endpoints =
      accessToken: ''
      authCode: ''
      authCodeWithoutLogin: ''
    ###

    constructor: (serviceContainer, @config, @cookie, @request) ->
      @accessToken = false
      @refreshToken = false
      @accessTokenParamName = 'access_token'
      @refreshTokenParamName = 'refresh_token'
      @options = @config.oauth2
      @endpoints = @options.endpoints
      if not @endpoints or not @endpoints.accessToken
        throw new Error('Oauth2::constructor error: at least endpoints.accessToken must be defined.')


    isAuthFailed: (response, error) ->
      ###
      Checks whether request results indicate auth failure, and clear tokens if necessary
      ###
      isFailed = (response?.error == 'invalid_grant' or response?.error == 'invalid_request')
      @_invalidateAccessToken() if isFailed
      isFailed


    isAuthAvailable: ->
      ###
      Do we have an auth right now?
      ###
      @_restoreTokens()
      !!(@accessToken or @refreshToken)


    clearAuth: ->
      @accessToken = null
      @refresToken = null
      @scope  = null
      @cookie.set('accessToken')
      @cookie.set('refreshToken')
      @cookie.set('oauthScope')
      @emit('auth.unavailable')


    injectAuthParams: (url, params, tryLuck = false) ->
      ###
      Adds to the given URL and params oauth access token if needed and returns them.
      @param {String} url
      @param {Object} params
      @param {Bool} tryLuck - try to make request with tokens, we have (previously params.skipAuth)
      @return {Future[Tuple[String, Object]]}
      ###
      if not @isAuthAvailable()
        Future.rejected('No OAuth2 tokens available.')
      else
        @_restoreTokens()
        if tryLuck
          url += ( if url.lastIndexOf('?') == -1 then '?' else '&' ) + "#{@accessTokenParamName}=#{@accessToken}"
          Future.resolved([url, params])
        else
          @_getTokensByAllMeans().spread (accessToken) =>
            url += ( if url.lastIndexOf('?') == -1 then '?' else '&' ) + "#{@accessTokenParamName}=#{accessToken}"
            [[url, params]]


    prepareAuth: ->
      @_getTokensByAllMeans()


    tryToAuth: ->
      ###
      In case of possible auto-login this should return resolved promise and rejected one otherwise
      ###
      Future.rejected('No auto-auth available')


    _getTokensByAllMeans: ->
      ###
      Tries to get auth tokens from different sources in this order:
      1. Local cache (cookies)
      2. Get new tokens by refresh token
      3. Initiate pluggable user authentication process.
      @return {Future[Tuple[String, String]]} access and refresh tokens
      ###
      @_restoreTokens()
      if @accessToken
        Future.resolved([@accessToken, @refreshToken])
      else
        if @refreshToken
          @_getTokensByRefreshToken()
        else
          Future.rejected('No refresh token available')



    _invalidateAccessToken: ->
      @accessToken = null
      @cookie.set('accessToken')


    _invalidateRefreshToken: ->
      @refreshToken = null
      @cookie.set('refreshToken')


    _restoreTokens: ->
      ###
      Loads saved tokens from cookies
      ###
      if not (@accessToken and @refreshToken)
        @accessToken  = @cookie.get('accessToken')
        @refreshToken = @cookie.get('refreshToken')
        @scope        = @cookie.get('oauthScope')

      return


    _storeTokens: (accessToken, refreshToken) ->
      ###
      Stores oauth tokens to cookies to be available after page refresh.
      @param {String} accessToken
      @param {String} refreshToken
      ###
      return if @accessToken == accessToken and @refreshToken == refreshToken

      @accessToken = accessToken
      @refreshToken = refreshToken
      @scope = @getScope()

      @cookie.set('accessToken', @accessToken, expires: 15)
      @cookie.set('refreshToken', @refreshToken, expires: 15)
      @cookie.set('oauthScope', @scope, expires: 15)

      @emit('auth.available')
      _console.log "Store tokens: #{accessToken}, #{refreshToken}"  if global.config.debug.oauth2


    getScope: ->
      ###
      Generates random scope for every browser (client) to prevent access-token auto-deletion when someone logging in
      from another computers (browsers)
      @return {String}
      ###
      if not @scope
        @scope = Math.round(Math.random() * 10000000)
      @scope


    grantAccessByUsernamePassword: (username, password) ->
      ###
      Tries to authenticate by username and password
      @param {String} username
      @param {String} password
      @return {Future} resolves when auth suceeded, fails in otherway
      ###
      result = @grantAccessTokenByPassword(username, password, @getScope())
      result.then (accessToken, refreshToken) =>
        @_onAccessTokenGranted(accessToken, refreshToken)

      result


    _onAccessTokenGranted: (accessToken, refreshToken) ->
      @_storeTokens(accessToken, refreshToken)
      @emit 'auth.available'


    #-----------------------------------------------------------------------------------------------------------------
    # Pure Oauth2

    grantAccessByExtensions: (url, params) ->
    ## Tries to grant accees by grant_type = extension (oneTimeKey, for instance)
      result = @_grantAccessTokenByExtensions(url, params, @getScope())
      result.then (accessToken, refreshToken) =>
        @_onAccessTokenGranted(accessToken, refreshToken)
      result


    _grantAccessTokenByExtensions: (url, params, scope) ->
      resultPromise = Future.single('Oauth2::_grantAccessTokenByExtensions')
      requestParams =
        grant_type: url
        client_id: @options.clientId
        scope: scope
        json: true

      requestParams = _.extend params, requestParams

      @request.get @endpoints.accessToken, requestParams, (result) ->
        if result
          resultPromise.resolve(result.access_token, result.refresh_token)
        else
          resultPromise.reject('Oauth2::_grantAccessTokenByExtensions unables to accuire access token: ' + JSON.stringify(result))

      resultPromise


    ## Получение токена по grant_type = password (логин и пароль)
    grantAccessTokenByPassword: (user, password, scope) ->

      resultPromise = Future.single('Oauth2::grantAccessTokenByPassword')

      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @options.clientId
        scope: scope
        json: true

      @request.get @endpoints.accessToken, params, (result) ->
        if result and result.access_token and result.refresh_token
          resultPromise.resolve(result.access_token, result.refresh_token)
        else
          resultPromise.reject('Oauth2::grantAccessTokenByPassword unables to accuire tokens:' + JSON.stringify(result))

      resultPromise


    grantAccessTokenByRefreshToken: (refreshToken, scope, retries = 1) ->
      ###
      Requests access_token by refresh_token
      @param {String} refreshToken
      @param {String} scope
      @param (optional){Int} retries Number of retries on fail before giving up
      @return {Future[Array[String, String]]} access_token and new refresh_token
      ###
      params =
        grant_type: 'refresh_token'
        client_id: @options.clientId
        scope: scope

      # User XDRS if needed, proxy it through XDRS on browser
      params['client_secret'] =
        if @config?.secrets?.client_secret
          @config.secrets?.client_secret
        else
          '#{client_secret}'

      params[@refreshTokenParamName] = refreshToken

      if not @_refreshTokenRequestPromise
        resultPromise = Future.single('OAuth2::grantAccessTokenByRefreshToken')
        @request.get @endpoints.accessToken, params, (result, err) =>
          if result
            if result.error # this means that refresh token is outdated
              resultPromise.resolve [null, null]
            else
              resultPromise.resolve [ result.access_token, result.refresh_token ]
          else if retries > 0
            _console.warn 'Error while refreshing oauth token! Will retry after pause... Error:', err
            Future.timeout(500).then =>
              @_refreshTokenRequestPromise = null
              @grantAccessTokenByRefreshToken(refreshToken, scope, retries - 1)
            .link(resultPromise)
          else
            resultPromise.reject(new Error("Failed to refresh oauth token! Reason: #{JSON.stringify(err)} "))

        @_refreshTokenRequestPromise = resultPromise

      @_refreshTokenRequestPromise


    _getTokensByRefreshToken: ->
      ###
      Refreshes auth tokens pair by the existing refresh token.
      @return {Future[Tuple[String, String]]} new access and refresh tokens
      ###
      return @_refreshPromise if @_refreshPromise
      @_refreshPromise = @grantAccessTokenByRefreshToken(@refreshToken, @getScope()).spread (grantedAccessToken, grantedRefreshToken) =>
        @_refreshPromise = null
        if grantedAccessToken and grantedRefreshToken
          @_storeTokens(grantedAccessToken, grantedRefreshToken)
          [[grantedAccessToken, grantedRefreshToken]]
        else
          @_invalidateRefreshToken()
          throw new Error('Failed to get auth token by refresh token: refresh token is outdated!')
      @_refreshPromise


    getAuthCodeByPassword: (login, password, scope) ->
      ###
      Accuires OAuth2 code via login and password for two-step code-auth
      ###
      promise = Future.single('Api::getAuthCodeByPassword promise')
      if !isBrowser
        promise.reject(new Error('It is only possible to get auth code at client side'))
      else
        params =
          response_type: 'code'
          client_id: @options.clientId
          login: login
          password: password
          format: 'json'
          scope: scope
          xhrOptions:
            withCredentials: true

        requestUrl = @endpoints.authCode
        @request.get requestUrl, params, (response, error) ->
          if response and response.code
            promise.resolve(response.code)
          else
            promise.reject(new errors.MegaIdAuthFailed('No auth code recieved. Response:'+ JSON.stringify(response) + JSON.stringify(error)))
      promise


    getAuthCodeWithoutPassword: (scope) ->
      ###
      Try to acquire auth Code. Succeeds only if user has been already logged in.
      Oauth2 server uses it's cookies to identify user
      ###
      promise = Future.single('Api::getAuthCodeWithoutPassword promise')
      if not isBrowser
        promise.reject(new Error('It is only possible to get auth code at client side'))
      else
        params =
          response_type: 'code'
          client_id: @options.clientId
          scope: scope
          format: 'json'
          xhrOptions:
            withCredentials: true

        requestUrl = @endpoints.authCodeWithoutLogin
        if not requestUrl
          return promise.reject('config.oauth2.endpoints.authCodeWithoutLogin parameter is required')
        @request.get requestUrl, params, (response, error) ->
          if response?.code
            promise.resolve(response.code)
          else
            promise.reject(new errors.MegaIdAuthFailed('No auth code recieved. Response: ' + JSON.stringify(response) + JSON.stringify(error)))
      promise


    grantAccessTokenByAuhorizationCode: (code, scope) ->
      ###
      Accuire tokens by OAuth2 code
      It uses special XDRS section to send secrets into auth server
      ###
      promise = Future.single('OAuth2::grantAccessTokenByAuthorizationCode promise')
      params =
        grant_type: 'authorization_code'
        code: code
        client_id: @options.clientId
        client_secret: '#{client_secret}'
        format: 'json'
        redirect_uri: @options.redirectUri
        scope: scope

      requestUrl = @endpoints.accessToken

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          promise.reject(new Error('No response from authorization server'))
      promise


    #-----------------------------------------------------------------------------------------------------------------
    # Oauth2 helpers

    doAuthCodeLoginByPassword: (login, password) ->
      ###
      This one use two-step auth process, to accuire OAuth2 code and then tokens
      ###
      @getAuthCodeByPassword(login, password, @getScope()).name('Oauth2::doAuthCodeLoginByPassword')
        .then (code) =>
          @grantAccessTokenByAuhorizationCode(code, @getScope())
        .then (accessToken, refreshToken, code) =>
          @_onAccessTokenGranted(accessToken, refreshToken)
          code


    doAuthCodeLoginWithoutPassword: ->
      ###
      This one is used for normal Auth2 procedure, not MegaId
      ###
      @getAuthCodeWithoutPassword(@getScope()).name('Api::doAuthCodeLoginWithoutPassword')
        .then (code) =>
          @grantAccessTokenByAuhorizationCode(code)
        .then (accessToken, refreshToken, code) =>
          @_onAccessTokenGranted(accessToken, refreshToken)
          code



    doAuthLogout: ->
      ###
      Logout for normal Auth2 procedure
      ###
      promise = Future.single('OAuth2::doAuthLogout promise')
      params =
        client_id: @options.clientId
        client_secret: '#{client_secret}'
        dataType: 'json',
        format: 'json'

      requestUrl = @endpoints.logout

      @request.get requestUrl, params, (result) =>
        if result and result.status == 'success'
          @_invalidateAccessToken()
          @_invalidateRefreshToken()
          promise.resolve()
        else
          promise.reject(new Error('Bad response from authorization server: ' + JSON.stringirfy(error)))
      promise



define [
  'underscore'
  'cord!isBrowser'
  'cord!utils/Future'
  'eventemitter3'
  'cord!request/errors'
  'cord!errors'
], (_, isBrowser, Future, EventEmitter, httpErrors, cordErrors) ->

  class OAuth2 extends EventEmitter

    ###
    OAuth2 auth module
    Required the following endpoints:
      accessToken -  url to Get access token via login/password or refresh tokem
      authCode - url to GET OAuth2 code via login/password
      authCodeWithoutLogin - url to GET OAuth2 code via CORS request for logged in user
      logout - url to logout out of server session for logged in user
    ###

    # name of auth configuration section inside `api` section
    @configKey: 'oauth2'

    accessTokenParamName: 'access_token'
    refreshTokenParamName: 'refresh_token'
    accessToken: null
    refreshToken: null

    cookiePath: '/'

    # default values are patterns for XDRS replacement
    _clientId: '#{clientId}'
    _clientSecret: '#{clientSecret}'

    _extRefreshName: '_external_refresh_in_progress_'

    # Wait for external refresh for no more than 30 seconds
    _maxExtRefreshWaitTime: 30


    constructor: (@options, @cookie, @request, @tabSync, @cookiePrefix = '') ->
      @logger = @request.logger
      @endpoints = @options.endpoints
      if not @endpoints or not @endpoints.accessToken
        throw new Error('OAuth2::constructor error: at least endpoints.accessToken must be defined.')
      # setting actual values of secret information if they are available
      if @options.secrets?.clientId?
        @_clientId = @options.secrets.clientId
      else
        @_clientId = global.config.secrets.clientId      if global.config?.secrets?.clientId?

      if @options.secrets?.clientSecret?
        @_clientSecret = @options.secrets.clientSecret
      else
        @_clientSecret = global.config.secrets.clientSecret  if global.config?.secrets?.clientSecret?


    isAuthFailed: (response) ->
      ###
      Checks whether request results indicate auth failure, and clear tokens if necessary
      ###
      isFailed = (response?.error == 'invalid_grant' or response?.error == 'invalid_request' or response?.error == 'unauthorized')
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
      @refreshToken = null
      @scope  = null
      Future.all([
        @cookie.set(@cookiePrefix + 'accessToken')
        @cookie.set(@cookiePrefix + 'refreshToken')
        @cookie.set(@cookiePrefix + 'oauthScope')
      ]).then =>
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
        Future.rejected(new cordErrors.AuthError('No OAuth2 tokens available.'))
      else
        @_restoreTokens()
        if tryLuck
          url += ( if url.lastIndexOf('?') == -1 then '?' else '&' ) + "#{@accessTokenParamName}=#{@accessToken}"
          Future.resolved([url, params])
        else
          @_getTokensByAllMeans()
            .catch (error) =>
              @logger.error('Clear refresh token, because of:', error)
              @_invalidateRefreshToken()
              throw error
            .spread (accessToken) =>
              url += ( if url.lastIndexOf('?') == -1 then '?' else '&' ) + "#{@accessTokenParamName}=#{accessToken}"
              [url, params]


    prepareAuth: ->
      @_getTokensByAllMeans()


    tryToAuth: ->
      ###
      In case of possible auto-login this should return resolved promise and rejected one otherwise
      ###
      Future.rejected(new cordErrors.AutoAuthError('No auto-auth available.'))


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
          Future.rejected(new cordErrors.AuthError('No refresh token available'))


    _invalidateAccessToken: ->
      @accessToken = null
      Future.try => @cookie.set(@cookiePrefix + 'accessToken')


    _invalidateRefreshToken: ->
      @refreshToken = null
      Future.try => @cookie.set(@cookiePrefix + 'refreshToken')


    _restoreTokens: ->
      ###
      Loads saved tokens from cookies
      ###

      # Never ever uncomment this line. Otherwise you'll face spoiling tokens in different browser tabs
      @accessToken  = @cookie.get(@cookiePrefix + 'accessToken')
      @refreshToken = @cookie.get(@cookiePrefix + 'refreshToken')
      @scope        = @cookie.get(@cookiePrefix + 'oauthScope')

      return


    _storeTokens: (accessToken, refreshToken, scope) ->
      ###
      Stores oauth tokens to cookies to be available after page refresh.
      @param {String} accessToken
      @param {String} refreshToken
      ###
      return Future.resolved() if @accessToken == accessToken and @refreshToken == refreshToken

      @accessToken = accessToken
      @refreshToken = refreshToken
      @scope = scope

      @emit('auth.available')

      Future.all([
        @cookie.set(@cookiePrefix + 'accessToken', @accessToken, expires: 15, path: @cookiePath)
        @cookie.set(@cookiePrefix + 'refreshToken', @refreshToken, expires: 15, path: @cookiePath)
        @cookie.set(@cookiePrefix + 'oauthScope', @scope, expires: 15, path: @cookiePath)
      ]).then =>
        @logger.log "Store tokens: #{accessToken}, #{refreshToken}"  if global.config.debug.oauth
        return


    generateScope: ->
      ###
      Generates random scope for every browser (client) to prevent access-token auto-deletion when someone logging in
      from another computers (browsers)

      The scope should be stored only in particular auth method callback.
      @return {String}
      ###
      Math.round(Math.random() * 10000000)


    grantAccessByUsernamePassword: (username, password) ->
      ###
      Tries to authenticate by username and password
      @param {String} username
      @param {String} password
      @return {Future} resolves when auth succeeded, fails otherwise
      ###
      scope = @generateScope()
      @grantAccessTokenByPassword(username, password, scope).spread (accessToken, refreshToken) =>
        @_onAccessTokenGranted(accessToken, refreshToken, scope)


    _onAccessTokenGranted: (accessToken, refreshToken, scope) ->
      @_storeTokens(accessToken, refreshToken, scope)


    #-----------------------------------------------------------------------------------------------------------------
    # Pure Oauth2

    grantAccessByExtensions: (url, params) ->
      ###
      Tries to grant access by grant_type = extension (oneTimeKey, for instance)
      ###
      scope = @generateScope()
      @_grantAccessTokenByExtensions(url, params, scope).spread (accessToken, refreshToken) =>
        @_onAccessTokenGranted(accessToken, refreshToken, scope)
        return


    _grantAccessTokenByExtensions: (url, params, scope) ->
      requestParams = _.extend {}, params,
        grant_type: url
        client_id: @_clientId
        scope: scope
        json: true

      @request.get(@endpoints.accessToken, requestParams)
        .rename('Oauth2::_grantAccessTokenByExtensions')
        .then (response) ->
          result = response.body
          [result.access_token, result.refresh_token, scope]
        .catchIf(
          (e) -> e instanceof httpErrors.InvalidResponse and e.response.statusCode == 400
          -> throw new cordErrors.AuthError()
        )


    grantAccessTokenByPassword: (user, password, scope) ->
      ###
      Получение токена по grant_type = password (логин и пароль)
      ###
      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @_clientId
        client_secret: @_clientSecret
        scope: scope
        json: true
        __noLogParams: [
          'password'
          'client_secret'
        ]

      @request.get(@endpoints.accessToken, params)
        .rename('Oauth2::grantAccessTokenByPassword')
        .then (response) ->
          result = response.body
          [result.access_token, result.refresh_token]
        .catchIf(
          (e) -> e instanceof httpErrors.InvalidResponse and e.response.statusCode == 400
          -> throw new cordErrors.AuthError()
        )


    grantAccessTokenByRefreshToken: (refreshToken, scope, retries = 15, retryTimeout = 500) ->
      ###
      Requests access_token by refresh_token
      @param {String} refreshToken
      @param {String} scope
      @param (optional){Int} retries Number of retries on fail before giving up
      @return {Future[Array[String, String]]} access_token and new refresh_token
      ###

      # There could be race conditions in one browser different tabs,
      # when few of them simultaneously try to get access_token by refresh_token, which could lead to cleansing all tokens

      if not @_refreshTokenRequestPromise
        @_refreshTokenRequestPromise = @getExternalRefreshPromise().catch =>

          # Set refresh lock, to let other tabs know we are in progress of getting new tokens, so wait for us
          @tabSync.set(@_extRefreshName, '1')

          params =
            grant_type: 'refresh_token'
            scope: scope
            client_id: @_clientId
            client_secret: @_clientSecret

          params[@refreshTokenParamName] = refreshToken

          @request.get(@endpoints.accessToken, params).then (response) =>
            result = response.body
            # Clear refresh promise, so the next time a new one will be created
            @_refreshTokenRequestPromise = null
            # Clear refresh lock, to let other tabs know we have new tokens
            @tabSync.set(@_extRefreshName)

            [result.access_token, result.refresh_token, scope]

          .catch (err) =>
            if err instanceof httpErrors.InvalidResponse
              result = err.response.body
              if result.error # this means that refresh token is outdated
                if result.error == 'invalid_client' # retries are helpless
                  throw new Error("Invalid clientId or clientSecret #{JSON.stringify(result)}")
                else if result.error = 'invalid_grant' # go to login
                  throw new cordErrors.AuthError("Unable to get access token by refresh token #{JSON.stringify(result)}")

            if retries > 0
              @logger.warn('Error while refreshing oauth token! Will retry after pause... Error:', JSON.stringify(err))
              Future.timeout(retryTimeout).then =>
                @_refreshTokenRequestPromise = null
                @grantAccessTokenByRefreshToken(refreshToken, scope, retries - 1, retryTimeout * 2)
            else
              throw new Error("Failed to refresh oauth token! No retries left. Reason: #{JSON.stringify(err)}")

      @_refreshTokenRequestPromise


    getExternalRefreshPromise: ->
      ###
      Check if there is any sign of other tab refreshing access_token
      Rejects if could not find any sing of refreshing by someone else
      Resolves if got new access and refresh tokens
      ###
      @tabSync.waitUntil(@_extRefreshName).then =>
        @_restoreTokens()
        [@accessToken, @refreshToken]


    _getTokensByRefreshToken: ->
      ###
      Refreshes auth tokens pair by the existing refresh token.
      @return {Future[Tuple[String, String]]} new access and refresh tokens
      ###
      return @_refreshPromise if @_refreshPromise
      scope = @scope ? @generateScope()
      @_refreshPromise = @grantAccessTokenByRefreshToken(@refreshToken, scope).spread (grantedAccessToken, grantedRefreshToken, scope) =>
        if grantedAccessToken and grantedRefreshToken
          @_storeTokens(grantedAccessToken, grantedRefreshToken, scope).then =>
            @_refreshPromise = null
            [grantedAccessToken, grantedRefreshToken, scope]
        else
          throw new cordError.AuthError('Failed to get auth token by refresh token: refresh token could be outdated!')
      @_refreshPromise


    getAuthCodeByPassword: (login, password, scope) ->
      ###
      Acquires OAuth2 code via login and password for two-step code-auth
      ###
      if not isBrowser
        Future.rejected(new Error('It is only possible to get auth code at client side'))
      else
        @request.get @endpoints.authCode,
          response_type: 'code'
          client_id: @_clientId
          login: login
          password: password
          format: 'json'
          scope: scope
          xhrOptions:
            withCredentials: true
        .then (response) ->
          response = response.body
          if response and response.code
            response.code
          else
            throw new cordErrors.MegaIdAuthFailed("No auth code recieved. Response: #{JSON.stringify(response)}")


    getAuthCodeWithoutPassword: (scope) ->
      ###
      Try to acquire auth Code. Succeeds only if user has been already logged in.
      Oauth2 server uses it's cookies to identify user
      ###
      if not isBrowser
        Future.rejected(new Error('It is only possible to get auth code at client side'))
      else
        requestUrl = @endpoints.authCodeWithoutLogin
        if requestUrl
          @request.get requestUrl,
            response_type: 'code'
            client_id: @_clientId
            scope: scope
            format: 'json'
            xhrOptions:
              withCredentials: true
          .then (response) ->
            result = response.body
            if result?.code
              result.code
            else
              throw new cordErrors.MegaIdAuthFailed("No auth code received. Response: #{JSON.stringify(result)}")
          .catchIf httpErrors.InvalidResponse, (err) ->
            if err.response.isServerError()
              throw err
            else
              throw cordErrors.MegaIdAuthFailed("Invalid auth code request! Response: #{JSON.stringify(err.response)}")
        else
          Future.rejected(new Error('config.api.oauth2.endpoints.authCodeWithoutLogin parameter is required'))


    grantAccessTokenByAuhorizationCode: (code, scope) ->
      ###
      Acquires tokens by OAuth2 code
      It uses special XDRS section to send secrets into auth server
      @return {Future<Tuple<String, String, String>>}
      ###
      @request.get @endpoints.accessToken,
        grant_type: 'authorization_code'
        code: code
        client_id: @_clientId
        client_secret: @_clientSecret
        format: 'json'
        redirect_uri: @options.redirectUri
        scope: scope
      .then (response) ->
        result = response.body
        if result and result.access_token and result.refresh_token
          [result.access_token, result.refresh_token, code]
        else
          throw new Error('Invalid response from authorization server: ' + JSON.stringify(response))


    #-----------------------------------------------------------------------------------------------------------------
    # Oauth2 helpers

    doAuthCodeLoginByPassword: (login, password) ->
      ###
      This one use two-step auth process, to accuire OAuth2 code and then tokens
      ###
      scope = @generateScope()
      @getAuthCodeByPassword(login, password, scope).nameSuffix('Oauth2::doAuthCodeLoginByPassword')
        .then (code) =>
          @grantAccessTokenByAuhorizationCode(code, scope)
        .spread (accessToken, refreshToken, code) =>
          @_onAccessTokenGranted(accessToken, refreshToken, scope)
          code


    doAuthCodeLoginWithoutPassword: ->
      ###
      This one is used for normal Auth2 procedure, not MegaId
      ###
      scope = @generateScope()
      @getAuthCodeWithoutPassword(scope).nameSuffix('Api::doAuthCodeLoginWithoutPassword')
        .then (code) =>
          @grantAccessTokenByAuhorizationCode(code, scope)
        .spread (accessToken, refreshToken, code) =>
          @_onAccessTokenGranted(accessToken, refreshToken, scope)
          code


    doAuthLogout: ->
      ###
      Logout for normal Auth2 procedure
      @return {Future<undefined>}
      ###
      @request.get @endpoints.logout,
        dataType: 'json',
        format: 'json'
        xhrOptions:
          withCredentials: true
      .then (response) =>
        result = response.body
        if result and result.status == 'success'
          Future.all [
            @_invalidateAccessToken()
            @_invalidateRefreshToken()
          ]
        else
          throw new Error("Bad response from authorization server: #{JSON.stringify(response)}")

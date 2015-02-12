define [
  'underscore'
  'cord!auth/OAuth2'
  'cord!utils/Future'
], (_, OAuth2, Future) ->

  class MegaplanId extends OAuth2
    ###
    MegaplanId auth module.
    Requires the following config to be set
      accessToken - request access tokens by megaplan ID
      inviteCode - process inviteCode by app-backend

    these ones used by OAuth2 module, so should be defined in config as well:
      authCode: ''
      authCodeWithoutLogin: ''
    ###

    constructor: (serviceContainer, config, @cookie, @request) ->
      @accessToken = null
      @refreshToken = null
      @accessTokenParamName = 'mega_id_token'
      @refreshTokenParamName = 'refresh_token'
      @options = config.megaplanId
      @endpoints = @options.endpoints


    isAuthFailed: (response, error) ->
      ###
      Checks whether request results indicate auth failure, and clear tokens if necessary
      ###
      isFailed = (response and
        (response.error == 'invalid_grant' or
         response?.error == 'invalid_request' or
         response.error == 'bad_megaplan_id'))
      @_invalidateAccessToken() if isFailed
      isFailed


    tryToAuth: ->
      ###
      In case of possible auto-login this should return resolved promise and rejected one otherwise
      ###
      @getAccessTokenByMegaId()


    getAccessTokenByMegaId: ->
      ###
      This one is used exclusevely for MegaId via backend (for security reasons)
      ###
      @getAuthCodeWithoutPassword(@getScope()).name('Api::getAccessTokenByMegaId')
        .then (code) =>
          @grantAccessTokenByMegaId(code, @getScope())
        .then (accessToken, refreshToken, code) =>
          @_storeTokens(accessToken, refreshToken)
          code


    grantAccessTokenByMegaId: (code, scope) ->
      ###
      Grant access token from backend, using Code accuired from MegaplanId on front-end
      Refreshing access tokens done via grantAccessTokenByRefreshToken
      ###
      promise = Future.single('OAuth2::grantAccessTokenByMegaId promise')
      params =
        grant_type: 'authorization_code'
        code: code
        scope: scope

      requestUrl = @endpoints.accessToken

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          if result?.error == 'bad_megaplan_id'
            promise.reject(new Error('bad_megaplan_id'))
          else
            promise.reject(new Error('No response from backend server (MegaId)'))
      promise


    getAccessTokenByInviteCode: (inviteCode) ->
      ###
      Grant access token via megaplan backend inviteCode
      ###
      @getAuthCodeWithoutPassword(@getScope()).name('Api::getAccessTokenByMegaId')
        .then (code) =>
          @grantAccessTokenByInviteCode(inviteCode, code, @getScope())
        .then (accessToken, refreshToken, code) =>
          @_storeTokens(accessToken, refreshToken)
          code


    grantAccessTokenByInviteCode: (inviteCode, code, scope) ->
      ###
      Convert invite auth into MegaplanId auth, and grant access tokes
      ###

      promise = Future.single('OAuth2::grantAccessTokenByInviteCode promise')
      params =
        inviteCode: inviteCode
        code: code
        scope: scope

      requestUrl = @endpoints.inviteCode

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          promise.reject(new Error(if _.isObject(result) and result.error then result.error else JSON.stringify(result)))
      promise


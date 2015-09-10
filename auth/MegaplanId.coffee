define [
  'underscore'
  'cord!auth/OAuth2'
], (_, OAuth2) ->

  class MegaplanId extends OAuth2
    ###
    MegaplanId auth module.
    Requires the following config to be set
      inviteCode - url to process inviteCode by app-backend
    ###

    @configKey: 'megaplanId'

    # need to be renamed to avoid conflict when used both auth methods in conjunction
    accessTokenParamName: 'mega_id_token'
    # refresh token name need not to be renamed
    refreshTokenParamName: 'refresh_token'


    isAuthFailed: (response) ->
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
      scope = @generateScope()
      @getAuthCodeWithoutPassword(scope).nameSuffix('Api::getAccessTokenByMegaId')
        .then (code) =>
          @grantAccessTokenByMegaId(code, scope)
        .spread (accessToken, refreshToken, code) =>
          @_storeTokens(accessToken, refreshToken, scope)
          code


    grantAccessTokenByMegaId: (code, scope) ->
      ###
      Grant access token from backend, using Code accuired from MegaplanId on front-end
      Refreshing access tokens done via grantAccessTokenByRefreshToken
      @return {Future<Tuple<String, String, String>>
      ###
      @request.get @endpoints.accessToken,
        grant_type: 'authorization_code'
        code: code
        scope: scope
      .then (response) =>
        result = response.body
        if result and result.access_token and result.refresh_token
          [result.access_token, result.refresh_token, code]
        else
          if result?.error == 'bad_megaplan_id'
            throw new Error('bad_megaplan_id')
          else
            throw new Error('No response from backend server (MegaId)')


    getAccessTokenByInviteCode: (inviteCode) ->
      ###
      Grant access token via megaplan backend inviteCode
      ###
      scope = @generateScope()
      @getAuthCodeWithoutPassword(scope).nameSuffix('Api::getAccessTokenByMegaId')
        .then (code) =>
          @grantAccessTokenByInviteCode(inviteCode, code, scope)
        .spread (accessToken, refreshToken, code) =>
          @_storeTokens(accessToken, refreshToken, scope)
          code


    grantAccessTokenByInviteCode: (inviteCode, code, scope) ->
      ###
      Convert invite auth into MegaplanId auth, and grant access tokes
      ###
      @request.get @endpoints.inviteCode,
        inviteCode: inviteCode
        code: code
        scope: scope
      .then (response) =>
        result = response.body
        if result and result.access_token and result.refresh_token
          [result.access_token, result.refresh_token, code]
        else
          throw new Error(if _.isObject(result) and result.error then result.error else JSON.stringify(result))

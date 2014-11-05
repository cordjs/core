define [
  'jquery.cookie'
  'underscore'
], ($, _) ->

  if global.config.localFsMode

    class BrowserCookie
      ###
      Simple dumb cookie emulation for the non-cookiable environment
      ###

      constructor: ->
        @_cookies = {}


      get: (name, defaultValue) ->
        @_cookies[name] ? defaultValue


      set: (name, value, params) ->
        @_cookies[name] = value
        true



  else

    class BrowserCookie

      get: (name, defaultValue) ->
        $.cookie(name) ? defaultValue


      set: (name, value, params) ->
        # Chrome does not like / path for local ip
        # _params = path: '/'
        _params = {}
        _.extend(_params, params) if params
        $.cookie name, value, _params
        true

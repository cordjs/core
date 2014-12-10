define ->

  class LocalCookie
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

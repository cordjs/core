define [
  'cord!utils/Future'
], (Future) ->

  class LocalCookie
    ###
    Simple dumb cookie emulation for the non-cookiable environment
    ###

    @storageKey: 'cookies'


    constructor: (@_cookies, @storage) ->


    get: (name, defaultValue) ->
      @_cookies[name] ? defaultValue


    set: (name, value, params) ->
      @_cookies[name] = value
      @storage.setItem(@constructor.storageKey, @_cookies)
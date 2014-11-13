define [
  'cookies'
], (Cookies) ->

  class ServerCookie

    constructor: (serviceContainer) ->
      @serviceContainer = serviceContainer
      @cookies = new Cookies serviceContainer.get('serverRequest'), serviceContainer.get('serverResponse')


    get: (name, defaultValue) =>
      value = @cookies.get name
      value ?= defaultValue


    set: (name, value, params) =>
      #prevent browser to use the same connection
      if @cookies.response._header
        return false
      else
        @cookies.response.shouldKeepAlive = false
        @cookies.set name, value, httpOnly: false
      true
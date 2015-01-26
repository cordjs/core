define [
  'cookies'
], (Cookies) ->

  class ServerCookie

    constructor: (serviceContainer) ->
      @serviceContainer = serviceContainer
      @cookies = new Cookies(serviceContainer.get('serverRequest'), serviceContainer.get('serverResponse'))
      @setValues = {} # Cookies set in current session, used to avoid retrieving old cookies on server-side


    get: (name, defaultValue) =>
      value = if @setValues[name] then @setValues[name].value else @cookies.get(name)
      value ?= defaultValue


    set: (name, value, params) =>
      # prevent browser to use the same connection
      if @cookies.response._header
        return false
      else
        @setValues[name] =
          value: value
        @cookies.response.shouldKeepAlive = false
        @cookies.set name, value, httpOnly: false
      true
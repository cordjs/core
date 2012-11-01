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
      @cookies.set name, value
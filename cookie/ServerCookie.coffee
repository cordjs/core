define [
  'cookies'
], (Cookies) ->

  class ServerCookie

    constructor: (request, response) ->
      @cookies = new Cookies request, response


    get: (name, defaultValue) =>
      value = @cookies.get name
      value ?= defaultValue


    set: (name, value, params) =>
      @cookies.set name, value
define [
  'cord!isBrowser',
  'cord!/cord/core/cookie/BrowserCookie'
  'cord!/cord/core/cookie/ServerCookie'
], (isBrowser, BrowserCookie, ServerCookie) ->

  class Cookie

    constructor: (request, response) ->
      if isBrowser
        @cookie = new BrowserCookie request, response
      else
        @cookie = new ServerCookie request, response


    get: (name, defaultValue) =>
      @cookie.get name, defaultValue


    set: (name, value, params) =>
      @cookie.set name, value, params

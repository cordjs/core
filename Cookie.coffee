define [
  'cord!isBrowser'
], (isBrowser) ->

  class Cookie

    constructor: (request, response) ->
      if isBrowser
        require ['cord!/cord/core/cookie/BrowserCookie'], (BrowserCookie) =>
          @cookie = new BrowserCookie request, response
      else
        require ['cord!/cord/core/cookie/ServerCookie'], (ServerCookie) =>
          @cookie = new ServerCookie request, response


    get: (name, defaultValue) =>
      @cookie.get name, defaultValue


    set: (name, value, params) =>
      @cookie.set name, value, params

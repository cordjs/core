define [
  'cord!isBrowser'
], (isBrowser) ->

  class Request

    constructor: (options) ->
      if isBrowser
        require ['cord!/cord/core/request/BrowserRequest'], (BrowserRequest) =>
          @request = new BrowserRequest options
      else
        require ['cord!/cord/core/request/ServerRequest'], (ServerRequest) =>
          @request = new ServerRequest options


    get: () ->
      @request.get.apply(@, arguments)
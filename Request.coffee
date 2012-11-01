define [
  'cord!isBrowser'
], (isBrowser) ->

  class Request

    @api = (options, callback) ->
      if isBrowser
        require ['cord!/cord/core/request/BrowserRequest'], (BrowserRequest) =>
          callback( new BrowserRequest options )
      else
        require ['cord!/cord/core/request/ServerRequest'], (ServerRequest) =>
          callback( new ServerRequest options )

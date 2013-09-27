define [
  'curly'
  'cord!Utils'
  'underscore'
], (curly, Utils, _) ->

  class ServerRequest

    constructor: (serviceContainer, options) ->
      defaultOptions =
        json: true

      @options = _.extend defaultOptions, options
      @serviceContainer = serviceContainer
      @METHODS = ['get', 'post', 'put', 'del']

      for method in @METHODS
        @[method] = ((method) =>
          (url, params, callback) =>
            @send(method, url, params, callback))(method)


    send: (method, url, params, callback) ->

      method = method.toLowerCase()
      _console.log('Unknown method:'+method) if method not in @METHODS
      method = 'del' if method is 'delete'

      argssss = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      argssss.url = argssss.params.url if !argssss.url and argssss.params.url?
      argssss.callback = params.callback if !argssss.callback and argssss.params.callback?

      if (method == 'get')
        options =
          query: argssss.params
          json: true
      else
        options =
          json: argssss.params

      startRequest = new Date() if global.config.debug.request
      curly[method] argssss.url, options, (error, response, body) =>
        if global.config.debug.request
          stopRequest = new Date()
          seconds = (stopRequest - startRequest) / 1000
          _console.log "ServerRequest (#{ seconds } s): #{method} #{argssss.url}"
          if error
            _console.error error
          if body and body.error or global.config.debug.request == "full"
            _console.log body

        argssss.callback body, error if typeof argssss.callback == 'function'

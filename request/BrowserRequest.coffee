define [
  'curly'
  'cord!Utils'
  'underscore'
], (curly, Utils, _) ->

  class BrowserRequest

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

      if params.xhrOptions
        options = params.xhrOptions
        delete params.xhrOptions
      else
        options = {}

      if (method == 'get')
        _.extend options,
          query: argssss.params
          json: true
          bust: false
      else
        _.extend options,
          query: ''
          json: argssss.params
          form: argssss.params.form

      _console.log "BrowserRequest: #{method} #{argssss.url}" if global.config.debug.request != "simple"
      startRequest = new Date() if global.config.debug.request
      window.curly[method] argssss.url, options, (error, response, body) =>
        if global.config.debug.request
          stopRequest = new Date()
          seconds = (stopRequest - startRequest) / 1000

          if global.config.debug.request == "simple"
            url = argssss.url.replace('http://127.0.0.1:1337/XDR/', '')
            url = url.replace(/(&|\?)?access_token=[^&]+/, '')
            _console.log "BrowserRequest ( #{ seconds } s): #{method} #{url}"
            if method isnt 'get'
              _console.log body
          else
            _console.log "========================================================================( #{ seconds } s)"
            _console.log "BrowserRequest: #{method} #{argssss.url}"
            _console.log argssss.params
            _console.log body if global.config.debug.request == "full"
            _console.log "========================================================================"

        if not error? and response.statusCode != 200
          error =
            statusCode: response.statusCode
            statusText: response.body._message

        argssss.callback body, error if typeof argssss.callback == 'function'

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

      _console.warn('Unknown method:' + method) if method not in @METHODS

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

      startRequest = new Date() if global.config.debug.request

      window.curly[method] argssss.url, options, (error, response, body) =>
        stopRequest = new Date()
        seconds = (stopRequest - startRequest) / 1000

        indexXDR = argssss.url.indexOf '/XDR/'
        url = argssss.url.slice(indexXDR + 5)
        url = url.replace(/(&|\?)?access_token=[^&]+/, '')

        if global.config.debug.request
          postal.publish 'logger.log.publish', { tags: ['request'], params: {method: method, url: url, seconds: seconds} }

        if not error? and response.statusCode != 200
          error =
            statusCode: response.statusCode
            statusText: response.body._message

          postal.publish 'logger.log.publish', { tags: ['request', 'error'], params: {method: method, url: url, seconds: seconds, errorCode: response.statusCode, errorText: response.body._message, requestParams: argssss.params} }

        argssss.callback body, error if typeof argssss.callback == 'function'

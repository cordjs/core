define [
  'request'
  'cord!Utils'
  'underscore'
  'postal'
], (curly, Utils, _, postal) ->

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

      _console.warn('Unknown method:' + method) if method not in @METHODS

      method = 'del' if method is 'delete'

      argssss = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      argssss.url = argssss.params.url if !argssss.url and argssss.params.url?
      argssss.callback = params.callback if !argssss.callback and argssss.params.callback?

      if method == 'get'
        options =
          qs: argssss.params
          json: true
          strictSSL: false
      else
        options =
          json: argssss.params
          strictSSL: false

      startRequest = new Date() if global.config.debug.request

      curly[method] argssss.url, options, (error, response, body) =>
        if not error? and response.statusCode != 200
          error =
            statusCode: response.statusCode
            statusText: response.body._message

        if global.config.debug.request
          stopRequest = new Date()
          seconds = (stopRequest - startRequest) / 1000

          loggerParams =
            method: method
            url: argssss.url
            seconds: seconds

          loggerTags = ['request', method]

          if global.config.debug.request == 'full'
            fullParams = requestParams: argssss.params
            fullParams['response'] = response.body if response?.body
            loggerParams = _.extend loggerParams, fullParams

          if error
            loggerTags.push 'error'
            errorParams = requestParams: argssss.params
            errorParams['errorCode'] = response.statusCode if response?.statusCode
            errorParams['errorText'] = response.body._message if response?.body?._message
            loggerParams = _.extend loggerParams, errorParams

          postal.publish 'logger.log.publish',
            tags: loggerTags
            params: loggerParams

        argssss.callback body, error if typeof argssss.callback == 'function'

define [
  'request'
  'cord!Utils'
  'underscore'
  'postal'
  'cord!utils/Future'
  'cord!request/Response'
], (curly, Utils, _, postal, Future, Response) ->

  class ServerRequest

    constructor: (options) ->
      defaultOptions =
        json: true

      @options = _.extend defaultOptions, options
      @METHODS = ['get', 'post', 'put', 'del']

      for method in @METHODS
        @[method] = ((method) =>
          (url, params, callback) =>
            @send(method, url, params, callback))(method)


    send: (method, url, params, callback) ->
      method = method.toLowerCase()

      if callback
        console.trace 'DEPRECATION WARNING: callback-style Request::send result is deprecated, use promise-style result instead!'

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

      promise = Future.single("ServerRequest::send(#{method}, #{url})")

      curly[method] argssss.url, options, (error, curlyResponse, body) =>
        response = Response.fromIncomingMessage(error, curlyResponse)
        if not error? and curlyResponse.statusCode != 200
          error =
            statusCode: curlyResponse.statusCode
            statusText: curlyResponse.body?._message

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
            fullParams['response'] = curlyResponse.body if curlyResponse?.body
            loggerParams = _.extend loggerParams, fullParams

          if error
            loggerTags.push 'error'
            errorParams = requestParams: argssss.params
            errorParams['errorCode'] = error.statusCode
            errorParams['errorText'] = error.statusText
            loggerParams = _.extend loggerParams, errorParams

          postal.publish 'logger.log.publish',
            tags: loggerTags
            params: loggerParams

        response.completePromise(promise)
        argssss.callback body, error if typeof argssss.callback == 'function'

      promise.then()

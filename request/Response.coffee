define [
  'underscore'
  'lodash'
  'cord!request/errors'
], (_, lodash, errors) ->

  class ResponseHeaders
    ###
    This is a storage for response headers
    ###

    constructor: (headers) ->
      @headers = {}
      @headers[key.toLowerCase()] = val for own key, val of headers
      @_headers = _(@headers)


    has: (name) ->
      @_headers.has(name.toLowerCase())


    get: (name) ->
      @headers[name.toLowerCase()]


    @fromXhr: (xhr) ->
      _parse = =>
        headers = {};
        headerStr = xhr.getAllResponseHeaders()
        return headers if not headerStr
        headerPairs = headerStr.split('\u000d\u000a');
        for headerPair in headerPairs
          # Can't use split() here because it does the wrong thing
          # if the header value has the string ": " in it.
          index = headerPair.indexOf('\u003a\u0020');
          if index > 0
            key = headerPair.substring(0, index);
            val = headerPair.substring(index + 2);
            headers[key] = val
        headers
      new ResponseHeaders(_parse())

  class Response
    ###
    This class represents an http response
    ###

    constructor: (@statusCode, @statusText, @headers, @body, @error = undefined) ->
      ###
      @param statusCode Integer status code of response
      @param statusText String status text
      @param headers object of ResponseHeaders
      @param body text of full body answer
      ###


    completePromise: (promise) ->
      ###
      Resolve or reject promise, depend on status code of response
      ###
      if @isSuccessful()
        promise.resolve(this)
      else if @error instanceof Error
        promise.reject(@error)
      else
        promise.reject(new errors.InvalidResponse(this))


    isClientError: -> 400 <= @statusCode < 500


    isServerError: -> 500 <= @statusCode < 600


    isOk: -> @statusCode == 200


    isForbidden: -> @statusCode == 403


    isNotFound: -> @statusCode == 404


    isInvalid: -> @statusCode < 100 or @statusCode >= 600


    isInformational: -> 100 <= @statusCode < 200


    isSuccessful: -> 200 <= @statusCode < 300



    @fromXhr: (error, xhr) ->
      ###
      Instantiate itself from XMLHttpRequest object
      ###
      if xhr
        new Response(
          xhr.statusCode,
          xhr.statusText,
          ResponseHeaders.fromXhr(xhr)
          xhr.body
        );
      else
        @_errorResponse(error)


    @fromIncomingMessage: (error, message) ->
      ###
      Instantiate itself from node's http.IncomingMessage object
      ###
      if message
        new Response(
          message.statusCode
          message.statusMessage
          new ResponseHeaders(lodash.cloneDeep(message.headers))
          message.body
        )
      else
        @_errorResponse(error)


    @_errorResponse: (error) ->
      ###
      Handles a case when there is only error available
      ###
      new Response(
        0
        'Invalid request'
        {}
        ''
        @_error(error)
      )


    @_error: (error) ->
      ###
      Error factory. Maps custom error to Http error
      ###
      switch
        when error and (error.message.indexOf('abort') != -1 or error.message.indexOf('cancel') != -1)
          new errors.Aborted(error.message)
        when error
          new errors.Network(error.message)
        else
          new errors.Network("Network error")

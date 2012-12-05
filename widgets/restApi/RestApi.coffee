define [
  'cord!Widget'
  'cord!Rest'
  'url'
  'querystring'
], ( Widget, Rest, url, qs ) ->

  class RestApi extends Widget

    show: (params, callback) ->
      serverRequest = @serviceContainer.get('serverRequest')
      serverResponse = @serviceContainer.get('serverResponse')

      options =
        #method: serverRequest.method
        type: serverRequest.method
        url: decodeURIComponent /^\/_restAPI\/(.*)$/.exec(serverRequest.url)[1]
        headers:
          'Accept': serverRequest.headers.accept

      request = (options) =>
        @request options, serverResponse, callback

      switch serverRequest.method

        when 'POST'
          body = ''
          serverRequest.on 'data', (data) ->
            body += data

          serverRequest.on 'end', (data) ->
            options.data = qs.parse body
            request options

        when 'GET'
          urlParts = url.parse serverRequest.url, true
          options.data = urlParts.query
          request options

    request: (options, res, callback) ->
      Rest.request options, (body, error, response) ->
        callback null, body

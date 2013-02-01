define [
  'cord!Widget'
  'cord!Rest'
  'url'
  'querystring'
], ( Widget, Rest, url, qs ) ->

  class RestApi extends Widget

    show: (params, callback) ->
      serverRequest = @container.get('serverRequest')
      serverResponse = @container.get('serverResponse')

      options =
        type: serverRequest.method
        url: decodeURIComponent /^\/_restAPI\/(.*)$/.exec(serverRequest.url)[1]
        headers:
          'Accept': 'application/json'
          'Content-Type': serverRequest.headers['content-Type'] || serverRequest.headers['content-type']

      request = (options) =>
        @request options, serverResponse, callback

      switch serverRequest.method

        when 'POST', 'PUT', 'DELETE'
          buffers = []
          serverRequest.on 'data', (chunk) ->
            buffers.push chunk

          serverRequest.on 'end', (data) ->
            body = Buffer.concat buffers
            #options.data = qs.parse body.toString 'utf8'
            #if serverRequest.headers['content-type'].toLowerCase().indexOf('multipart/form-data') >= 0
            options.body = body
            request options

        when 'GET'
          urlParts = url.parse serverRequest.url, true
          options.data = urlParts.query
          request options

    request: (options, res, callback) ->
      Rest.request options, (body, error, response) ->
        #For debug reasons
        if response.statusCode != 200
          console.log 'API ERROR:', body
          console.log response.body
        callback null, body

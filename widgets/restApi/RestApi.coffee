define [
  'cord!Widget'
  'cord!Rest'
  'url'
  'querystring'
], ( Widget, Rest, url, qs ) ->

  class RestApi extends Widget

    showAction: (action, params, callback, req, res) ->
#      console.log arguments
      options =
        method: req.method
        url: decodeURIComponent params.restPath
        headers:
          'Accept': req.headers.accept
#          'Accept-encoding': req.headers.accept-encoding

      request = (options) =>
        @request options, res, callback

      switch req.method

        when 'POST'
          body = ''
          req.on 'data', (data) ->
            body += data

          req.on 'end', (data) ->
            options.data = qs.parse body
            request options

        when 'GET'
          urlParts = url.parse req.url, true
          options.data = urlParts.query
          request options

    request: (options, res, callback) ->
      Rest.request options, (body, error, response) ->
        console.log arguments
#        res.writeHead response[ 'statusCode' ], 'Content-Type': response.headers[ 'content-type' ]
        callback null, body

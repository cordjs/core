define [
  'cord!Widget'
  'cord!Rest'
  'url'
  'querystring'
], ( Widget, Rest, url, qs ) ->

  class RestApi extends Widget

    showAction: (action, params, callback) ->
      options =
        method: @repo.getRequest().method
        url: decodeURIComponent params.restPath
        headers:
          'Accept': @repo.getRequest().headers.accept

      request = (options) =>
        @request options, @repo.getResponse(), callback

      switch @repo.getRequest().method

        when 'POST'
          body = ''
          @repo.getRequest().on 'data', (data) ->
            body += data

          @repo.getRequest().on 'end', (data) ->
            options.data = qs.parse body
            request options

        when 'GET'
          urlParts = url.parse @repo.getRequest().url, true
          options.data = urlParts.query
          request options

    request: (options, res, callback) ->
      Rest.request options, (body, error, response) ->
        callback null, body

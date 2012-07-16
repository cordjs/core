define [
  'cord!/cord/core/isBrowser'
], ( isBrowser ) ->

  class Rest

    get: (url) ->
      

    post: (url, data) ->

      require ['http', 'querystring'], (http, querystring) ->
        data = querystring.stringify data

        options =
          host: url
          port: '80'
          path: '/U2Search/TableFilters/show.json'
          method: 'POST'
          headers:
            'Content-Type': 'application/x-www-form-urlencoded'
            'Content-Length': data.length

        postReq = http.request options, (res) ->
          res.setEncoding 'utf8'
          res.on 'data', (chunk) ->
            console.log 'Response: ', chunk

#        postReq.write data
        postReq.end()

  new Rest

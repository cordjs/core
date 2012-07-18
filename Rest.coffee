define [
  'underscore'
  'cord!/cord/core/isBrowser'
], ( _, isBrowser ) ->

  class Rest

    get: (data, callback) ->
      options = _.extend {
        method: 'GET'
      }, data

      @request options, callback

    post: (data, callback) ->
      options = _.extend {
        method: 'POST'
      }, data

      @request options, callback

    request: (options, callback) ->
      options = _.extend {
                  method: 'GET'
                }, options

      console.log 'Rest: ', options.url
      if isBrowser
        require [ 'jquery' ], ($) ->
          $.ajax
            type: options.method
            url: options.url
            data: options.data
            dataType: if options.json then 'json' else 'html'

          .done (body) ->
            callback? body

          .error ( error ) ->
            console.log 'error, ', error

          .complete ( error ) ->
            console.log 'complete, ', arguments

      else
        require [ 'request', 'querystring', 'url' ], (request, qs, url) ->
#          console.log 'Rest: send val'
#          console.log 'urlParse: ', url.parse '//json.text'
          options.url += '?' + qs.stringify options.data if options.data?
          request options, (error, response, body) ->
#            console.log 'Rest options:', options
            console.log 'Rest error:', error
            callback? body

  new Rest

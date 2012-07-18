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


    browserUrlParse: (sUrl) ->
      if isBrowser
        urlParse = document.createElement 'a'
        urlParse.href = sUrl

        urlParse


    browserRequest: (options, callback) ->
      $.ajax
        type: options.method
        url: options.url
        data: options.data
        dataType: if options.json then 'json' else 'html'

      .done (body) ->
         callback? body

      .error ( error ) ->
        console.log 'error, ', error

#      .complete ( error ) ->
#          callback? body


    request: (options, callback) ->
      options = _.extend {
                  method: 'GET'
                }, options

      console.log 'Rest: ', options.url
      if isBrowser
        require [ 'jquery' ], ($) =>
          restUrl = @browserUrlParse options.url
          currUrl = @browserUrlParse '/'

          if restUrl.hostname isnt currUrl.hostname
            if options.method is 'GET'
              options.url = "#{ options.url }?#{ $.param options.data }"

            options.url = "/_restAPI/#{ encodeURIComponent options.url }"

          @browserRequest options, callback

      else
        require [ 'request', 'querystring' ], (request, qs) ->
          options.url += '?' + qs.stringify options.data if options.data?
          request options, (error, response, body) ->
#            console.log 'Rest error:', error
#            console.log 'Rest body:', body
            callback? body, error, response

  new Rest

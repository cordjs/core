define [
  'underscore'
  ( if window? then 'jquery' else '' )
], ( _, $ ) ->

  class Rest

    get: (data, callback) ->
      options = _.extend {
        type: 'GET'
      }, data

      @request options, callback


    post: (data, callback) ->
      options = _.extend {
        type: 'POST'
      }, data

      @request options, callback


    browserUrlParse: (sUrl) ->
      if $
        urlParse = document.createElement 'a'
        urlParse.href = sUrl

        urlParse

    browserRequest: (options, callback) ->
      options.dataType = 'jsonp' if options.crossDomain?
      $.ajax(options)

    request: (options, callback) ->
      options = _.extend {
                  type: 'GET'
                }, options

      # is browser
      if $
        restUrl = @browserUrlParse options.url
        currUrl = @browserUrlParse '/'

        if restUrl.hostname isnt currUrl.hostname
            # todo: Нужно позже разобраться с кроссдоменным ajax через клиента, это возможно :)
#            if options.method is 'GET'
#              options.crossDomain = true
##              options.url = "#{ options.url }"#?#{ $.param options.data }"
#            else
#              options.url = "/_restAPI/#{ encodeURIComponent options.url }"
#              options.url = "#{ options.url }?#{ $.param options.data }"

            options.url = "/_restAPI/#{ encodeURIComponent options.url }"

        @browserRequest options, callback

      else

        require [ 'request', 'querystring' ], (request, qs) ->
          options.method = options.type
          delete options.type

          if options.dataType is 'json'
            options.json = 'true'
            delete options.dataType

          options.url += '?' + qs.stringify options.data if options.data?
          request options, (error, response, body) ->
            callback? body, error, response

            if !error and response.statusCode is 200
              ajaxCallbacks.success(body)
            else
              ajaxCallbacks.error(body)

        # сделано для того, чтобы сервер умел понимать Ajax .success, .error как jQuery
        # это нужно для совместимости с моделями Spine без их потрашения
        ajaxCallbacks =
          success: ->
          error: ->

        returnCallbacks =
          success: (callback) ->
            ajaxCallbacks.success = callback
            returnCallbacks

          error: (callback) ->
            ajaxCallbacks.error = callback
            returnCallbacks


  new Rest

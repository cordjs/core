define [
  'request'
  './Request'
  './Response'
  'underscore'
], (curlySender, Request, Response, _) ->

  class ServerRequest extends Request

    defaultOptions:
      strictSSL: false


    createResponse: (error, xhr) ->
      Response.fromIncomingMessage(error, xhr)


    getSender: ->
      curlySender


    getExtendedRequestOptions: (method, params) ->
      options =
        if method == 'get'
          qs: params
          json: true
        else
          json: params
      _.extend({}, @options, options)

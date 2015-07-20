define [
  'request'
  './AbstractRequest'
  './Response'
  'underscore'
], (curlySender, AbstractRequest, Response, _) ->

  class ServerRequest extends AbstractRequest

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

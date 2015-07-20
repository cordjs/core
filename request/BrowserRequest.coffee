define [
  'curly'
  './Request'
  './Response'
], (curly, Request, Response) ->

  class BrowserRequest extends Request

    defaultOptions:
      bust: false


    getExtendedRequestOptions: (method, params) ->
      xhrOptions = params.xhrOptions or {}
      options =
        if method == 'get'
          query: params
          json: true
        else
          query: ''
          json: params
          form: params.form
      _.extend({}, @options, options, xhrOptions)


    createResponse: (error, xhr) ->
      Response.fromXhr(error, xhr)


    getSender: ->
      curly

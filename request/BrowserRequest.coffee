define [
  'curly'
  './AbstractRequest'
  './Response'
], (curly, AbstractRequest, Response) ->

  class BrowserRequest extends AbstractRequest

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

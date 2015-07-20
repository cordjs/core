define [
  'curly'
  './Request'
], (curly, Request) ->

  class BrowserRequest extends Request

    getSender: ->
      window.curly

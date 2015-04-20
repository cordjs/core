define [
  'cord!Widget'
], (Widget) ->

  class Error extends Widget

    @params:
      error: ':ctx'
      widget: ':ctx'

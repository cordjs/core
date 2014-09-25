define [
  'cord!Widget'
], (Widget) ->

  class TimerWithToolbar extends Widget

    cssClass: 'b-cord-profiler-timer-with-toolbar'
    css: true

    @initialCtx:
      timer: null
      highlightInfo: {}

    @params:
      timer: ':ctx'
      highlightInfo: ':ctx'


    expandSlowestPath: ->
      @childByName.rootTimer?.expandSlowestPath()

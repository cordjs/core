define [
  'cord!Widget'
], (Widget) ->

  class Panel extends Widget

    cssClass: 'b-sdf-profiler-panel'
    css: true

    @initialCtx:
      timers: []

    @params:
      timers: ':ctx'


    expandSlowestPath: ->
      @childByName.timerList?.expandSlowestPath()

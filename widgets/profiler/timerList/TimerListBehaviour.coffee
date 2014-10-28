define [
  'cord!Behaviour'
  'underscore'
], (Behaviour, _) ->

  class TimerListBehaviour extends Behaviour

    @widgetEvents:
      timers: 'onTimersChange'


    init: ->
      @widget.expandSlowestPath() if @widget.ctx.expandSlowest
      @widget.pushTimersHighlightInfo()


    onTimersChange: (data) ->
      _.difference(data.value, data.oldValue).map (timer) =>
        @insertChildWidget '//profiler/Timer',
          name: "tim#{timer.id}"
          timerInfo: timer
          rootTimerInfo: @widget.ctx.rootTimerInfo
          level: @widget.ctx.nextLevel

define [
  'cord!Widget'
], (Widget) ->

  class TimerWithToolbar extends Widget

    cssClass: 'b-cord-profiler-timer-with-toolbar'
    css: true

    @initialCtx:
      timer: null
      timerName: null
      highlightInfo: {}

    @params:
      timer: 'onTimerParamChange'
      highlightInfo: ':ctx'


    onTimerParamChange: (timer) ->
      maxTime = timer.totalTime
      half    = maxTime / 2
      quarter = maxTime / 4

      timer.nameId = 'tim'+timer.id
      if timer.totalTime >= half
        timer.overHalf = true
      else if timer.totalTime > quarter
        timer.overQuarter = true

      timer.finished = not timer.finished? or timer.finished

      @ctx.set timer: timer

    expandSlowestPath: ->
      @childByName.rootTimer?.expandSlowestPath()
define [
  'cord!Widget'
  'underscore'
], (Widget, _) ->

  class TimerList extends Widget

    behaviourClass: false
    rootTag: 'ul'
    cssClass: 'b-cord-profiler-timer-list'
    css: true

    @initialCtx:
      timers: []
      nextLevel: 0

    @params:
      timers: 'onTimersParamChange'
      level: (number) ->
        @cssClass += ' level-color-' + number % 6
        @ctx.set nextLevel: number + 1


    onTimersParamChange: (timers) ->
      redTimer = @_getSlowestTimer(timers)

      maxTime = redTimer.totalTime
      half    = maxTime / 2
      quarter = maxTime / 4

      # adding relative style indicators to the timers info
      for tim in timers
        if tim == redTimer
          tim.slowest = true
        else if tim.totalTime >= half
          tim.overHalf = true
        else if tim.totalTime > quarter
          tim.overQuarter = true

      @ctx.set timers: timers


    _getSlowestTimer: (timers) ->
      _.max timers, (x) -> x.totalTime

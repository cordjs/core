define [
  'cord!Widget'
  'underscore'
], (Widget, _) ->

  roundTime = (x) -> (parseFloat(x) / 1000).toFixed(3)

  class Panel extends Widget

    cssClass: 'b-cord-profiler-panel'
    css: true

    @initialCtx:
      timers: []
      initTime: 0.0
      minimized: true

    @params:
      timers: 'onTimersParamChange'
      initTime: (time) -> @ctx.set(initTime: roundTime(time))


    onTimersParamChange: (timers) ->
      redTimer = @_getSlowestTimer(timers)

      maxTime = redTimer.totalTime
      half = maxTime / 2
      quarter = maxTime / 4

      # adding relative style indicators to the timers info
      for tim in timers
        tim.nameId = 'tim'+tim.id
        if tim == redTimer
          tim.slowest = true
        else if tim.totalTime >= half
          tim.overHalf = true
        else if tim.totalTime > quarter
          tim.overQuarter = true

        tim.finished = not tim.finished? or tim.finished

      @ctx.set timers: timers


    onShow: ->
      @addDynClass('minimized')


    toggleFullPanel: (show) ->
      newValue =
        if show?
          not show
        else
          not @ctx.minimized
      @ctx.set minimized: newValue


    _getSlowestTimer: (timers) ->
      _.max(timers, (x) -> x.totalTime)

define [
  'cord!Widget'
  'underscore'
], (Widget, _) ->

  class TimerList extends Widget

    cssClass: 'b-cord-profiler-timer-list'
    css: true

    @initialCtx:
      highlightInfo: {}
      timers: []
      nextLevel: 0
      rootTimerInfo: null
      expandSlowest: false

    @params:
      highlightInfo: 'onHighlightInfoParamChange'
      timers: 'onTimersParamChange'
      rootTimerInfo: ':ctx'
      level: (number) ->
        @cssClass += ' level-color-' + number % 6
        @ctx.set nextLevel: number + 1
      expandSlowest: ':ctx' # used in behaviour to initiate expand slowest immediately after first render

    @childEvents:
      ':any actions.highlight-wait-deps': (payload) -> @emit 'actions.highlight-wait-deps', payload


    onHighlightInfoParamChange: (infoMap) ->
      @ctx.set highlightInfo: infoMap
      @pushTimersHighlightInfo()


    onTimersParamChange: (timers) ->
      redTimer = @_getSlowestTimer(timers)

      maxTime = redTimer.totalTime
      half    = maxTime / 2
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


    expandSlowestPath: ->
      redTimer = @_getSlowestTimer(@ctx.timers)
      index = @ctx.timers.indexOf(redTimer)
      i = -1
      # identify child Timer widget related to the slowest timer by position and recursively call "expand" for it
      for child in @children
        i++ if _.isFunction(child.expandSlowestPath)
        if i == index
          child.expandSlowestPath()
          break
      @ctx.set expandSlowest: false


    pushTimersHighlightInfo: ->
      ###
      Dynamically pushes highlight info for every child timer widget.
      Specially formed widget name (using timer id) is used to correctly identify widget for every timer.
      ###
      for id, info of @ctx.highlightInfo when @childByName["tim#{id}"]?
        @childByName["tim#{id}"].setHighlightInfo(info)


    _getSlowestTimer: (timers) ->
      _.max(timers, (x) -> x.totalTime)

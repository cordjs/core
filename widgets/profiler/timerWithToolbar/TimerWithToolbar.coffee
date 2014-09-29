define [
  'cord!Widget'
], (Widget) ->

  calculateDeepHighlight = (info, timers) ->
    ###
    Recursively walks through tree of `timers` and constructs related tree with highlighting info
     according to the given timer ids in `info`
    @param Object info dependency timer ids
    @param Array[Object] timers
    @return Object
    ###
    result =
      bubbleType: 'none'
      timers: {}

    for timer in timers
      hInfo = type: 'none'
      if timer.id == info.selectedTimerId
        hInfo.type = 'selected'
      else if timer.id in info.depTimerIds
        hInfo.type = 'dep'

      if timer.children?
        childRes = calculateDeepHighlight(info, timer.children)
        hInfo.children = childRes.timers
        hInfo.type = childRes.bubbleType if hInfo.type == 'none'
        hInfo.type = 'selected-dep-parent' if hInfo.type == 'selected' and childRes.bubbleType == 'dep-parent'
        hInfo.type = 'dep-dep-parent' if hInfo.type == 'dep' and childRes.bubbleType == 'dep-parent'

      result.timers[timer.id] = hInfo

      if hInfo.type in ['dep', 'dep-parent', 'dep-dep-parent']
        result.bubbleType = 'dep-parent'
      else if hInfo.type in ['selected', 'selected-dep-parent'] and result.bubbleType != 'dep-parent'
        result.bubbleType = 'selected-parent'
      else if result.bubbleType == 'none'
        result.bubbleType = hInfo.type

    result


  class TimerWithToolbar extends Widget

    cssClass: 'b-cord-profiler-timer-with-toolbar'
    css: true

    @initialCtx:
      timer: null
      isSlowestDisable: true

    @params:
      timer: 'onTimerParams'

    @childEvents:
      'rootTimer actions.highlight-wait-deps': 'highlightWaitDeps'


    onTimerParams: (timer) ->
      @ctx.set isSlowestDisable: not timer.children


    expandSlowestPath: ->
      @childByName.rootTimer.expandSlowestPath()


    highlightWaitDeps: (highlightInfo) ->
      timersInfo = calculateDeepHighlight(highlightInfo, [@ctx.timer]).timers
      @childByName.rootTimer.setHighlightInfo(timersInfo[@ctx.timer.id])

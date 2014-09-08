define [
  'cord!Widget'
], (Widget) ->

  roundTime = (x) -> parseFloat(x).toFixed(3)


  class Timer extends Widget
    ###
    Recursive widget representing one timer with it's children
    ###

    rootTag: 'li'
    cssClass: 'b-sdf-profiler-timer'
    css: true

    @initialCtx:
      name: ''
      syncTime: 0.0
      startTime: 0.0
      totalTime: 0.0
      children: []
      showChildren: false
      level: 0 # need to set different contrast background colors for nested timers
      isSlowest: false
      overHalf: false
      overQuarter: false
      rootTimerInfo: {}
      showDesc: false
      expandSlowest: false

    @params:
      'timerInfo, rootTimerInfo': 'onTimerInfoParamChange'
      level: (level) ->
        @ctx.set
          level: level
          timelineContainerLeft: 50 - level
          guardLevel: (level - 1) % 6


    onTimerInfoParamChange: (info, rootInfo) ->
      @ctx.set
        name: info.name
        syncTime: roundTime(info.syncTime)
        startTime: roundTime(info.startTime)
        totalTime: roundTime(info.totalTime)
        ownPureExecTime: roundTime(info.ownAsyncTime)
        totalPureExecTime: roundTime(info.pureExecTime)
        ownTaskCount: info.ownTaskCount
        children: info.children
        isSlowest: !!info.slowest
        overHalf: !!info.overHalf
        overQuarter: !!info.overQuarter

      # calculating timeline graph coordinates relatively to the root timer
      root = rootInfo ? info
      rootStart = root.startTime
      rootTotal = root.totalTime

      leftToPercent = (time) -> (time - rootStart) / rootTotal * 100
      widthToPercent = (time) -> time / rootTotal * 100

      timelines = []

      if info.asyncTime?
        timelines.push
          type: 'async'
          left: leftToPercent(info.startTime + info.syncTime)
          width: widthToPercent(info.asyncTime)

      timelines.push
        type: 'exec'
        left: leftToPercent(info.startTime)
        width: widthToPercent(info.pureExecTime)

      timelines.push
        type: 'sync'
        left: leftToPercent(info.startTime)
        width: widthToPercent(info.ownAsyncTime)


      @ctx.set
        timelines: timelines
        rootTimerInfo: root
        guardLeft: leftToPercent(info.startTime) - 1


    toggleChildren: (show) ->
      ###
      Switches children state between collapsed and shown.
      @param (optional)Boolean show if true - show, else - collapse, if not set - toggle from previous state
      ###
      newValue =
        if show?
          !!show
        else
          not @ctx.showChildren
      @ctx.set showChildren: newValue


    toggleDesc: (show) ->
      ###
      Switches description state between collapsed and shown.
      @param (optional)Boolean show if true - show, else - collapse, if not set - toggle from previous state
      ###
      newValue =
        if show?
          !!show
        else
          not @ctx.showDesc
      @ctx.set showDesc: newValue


    expandSlowestPath: ->
      if @childByName.childTimers?
        @childByName.childTimers.expandSlowestPath()
      else
        @ctx.set expandSlowest: true
        # this is temporary state, need to reset if after re-render
        @once 're-render.complete', ->
          @ctx.set expandSlowest: false
      @toggleChildren(true)

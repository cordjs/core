define [
  'cord!Widget'
  'underscore'
], (Widget, _) ->

  roundTime = (x) -> parseFloat(x).toFixed(3)


  class Timer extends Widget
    ###
    Recursive widget representing one timer with it's children
    ###

    rootTag: 'li'
    cssClass: 'b-sdf-profiler-timer'
    css: true

    @initialCtx:
      highlightType: 'none'
      name: ''
      syncTime: 0.0
      startTime: 0.0
      totalTime: 0.0
      children: []
      childrenHighlightInfo: {}
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

    @childEvents:
      'childTimers actions.highlight-wait-deps': (payload) -> @emit 'actions.highlight-wait-deps', payload


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
        timerInfo: info
        waitDeps: info.waitDeps.join(', ')

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


    setHighlightInfo: (info) ->
      ###
      Updates wait dependency highlight state pushed from the parent TimerList widget
      @public
      @param Object info struct with precalculated highlighting type and child timers info
      ###
      @ctx.set highlightType: info.type
      @ctx.set childrenHighlightInfo: info.children if info.children


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


    triggerHighlightWaitDeps: ->
      ###
      Triggers action to highlight all timers which caused the current timer to move forward and complete.
      ###
      # excluding first chunk of wait dependencies because it's always obviously parent timer's call-stack
      cutSync = _.rest(@ctx.timerInfo.waitDeps)
      # taking into account only top-most caller timer
      firstDeps = cutSync.map (x) -> x[0]
      @emit 'actions.highlight-wait-deps',
        selectedTimerId: @ctx.timerInfo.id
        depTimerIds: _.uniq(firstDeps)


    expandSlowestPath: ->
      if @childByName.childTimers?
        @childByName.childTimers.expandSlowestPath()
      else
        @ctx.set expandSlowest: true
        # this is temporary state, need to reset if after re-render
        @once 're-render.complete', =>
          @ctx.set expandSlowest: false
      @toggleChildren(true)

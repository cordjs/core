define [
  'eventemitter3'
  'underscore'
  'cordjs-zone'
], (EventEmitter, _, rootZone) ->

  # private vars

  # index of all timers by id
  timersById = {}
  # timers id generator
  timerIdCounter = if CORD_IS_BROWSER then 1000 else 1 # weak protection against ID conflicts

  # Synchronous timers "call-stack". Useful to detect wait-dependencies between timers and to prevent double accounting
  syncTimerStack = []

  # Profiling zone

  profilerRootZone = rootZone.fork
    enqueueTask: ->
      @timer().asyncDetected = true
      @timer().counter++

    dequeueTask: ->
      @timer().counter--

    beforeTask: (isClearFn = false) ->
      timer = @timer()
      timer.counter++
      if not isClearFn
        timer.waitDeps.push(syncTimerStack.map (x) -> x.id) if syncTimerStack.length
        syncTimerStack.push(id: timer.id, decrement: 0.0)
        @_curTaskSyncStart = fixTimer()

    afterTask: (isClearFn = false) ->
      timer = @timer()
      if not isClearFn
        # we need to reduce own time by the children timers sync time to avoid double-accounting
        curTaskTime = fixTimer(@_curTaskSyncStart)
        timer.ownAsyncTime += curTaskTime - syncTimerStack.pop().decrement
        syncTimerStack[syncTimerStack.length - 1].decrement = curTaskTime if syncTimerStack.length
        timer.ownTaskCount++
        @_curTaskSyncStart = 0
      else
        timer.clearTaskCount++
      timer.counter--
      if timer.counter == 0
        if timer.asyncDetected
          timer.asyncTime = fixTimer(timer.asyncTime)
        timer.complete() if timer.childCompleteCounter == 0

    onError: (err) ->
      timer = @timer()
      console.error 'onError', timer.name, timer.counter, err
      timer.error = err
      throw err

    timer: -> timersById[@timerId]

    timerId: 0
    _curTaskSyncStart: 0



  pr = _.extend new EventEmitter,
    newRoot: (name, fn) ->
      @timer(name, true, fn)


    timer: (name, newRoot, fn) ->
      ###
      Creates a new timer with the given name and calls and profiles the given function "inside" of that timer.
      @param String name timer name
      @param (optional)Boolean newRoot if true, creates a new root-level timer (default - false)
      @param Function fn the profiled function
      @return Any the profiled function's return value
      ###
      if typeof newRoot == 'function'
        fn = newRoot
        newRoot = false
      else
        newRoot = !!newRoot

      # if the current zone doesn't have timerId than we should use profilerRootZone to enable profiling hooks,
      #  so the new timer in this case will be created as root-level timer regardless of the newRoot value
      myZone = if newRoot or not zone.timerId? then profilerRootZone else zone

      result = undefined

      timerId = timerIdCounter++
      timersById[timerId] = timer = new ProfilingTimer(timerId, name, myZone.timerId)

      myZone.fork
        timerId: timerId
        _curTaskSyncStart: 0
      .run ->
        timer.startTime = fixTimer(timer.relativeStartTime)
        start = fixTimer()
        result = fn()
        timer.syncTime = fixTimer(start)
        timer.asyncTime = fixTimer()
        result


    call: (context, fnName, args...) ->
      ###
      Calls function with name `fn` applied to `context` object within separate profiler timer with auto-generated name
      @param Object context
      @param String fnName
      @param Any.. args the function arguments
      @return Any the function calling result
      ###
      pr.timer "#{context.constructor.name}::#{fnName}()", ->
        context[fnName].apply(context, args)


    printTimer: (timer) ->
      console.log '-------------------------------------------------'
      console.log 'Timer', timer.name
      console.log JSON.stringify(timer, null, 2)


    patch: (obj, fnName, index = null, field = null) ->
      ###
      Patches method `fnName` of `obj` to wrap that method into profiler timer.
      @param Object obj
      @param String fnName name of the function
      @param (optional)Int index index of the function argument to include into auto-generated timer name
      @param (optional)String field field name of that function argument (see `index`) to include in the timer name
      ###
      origFn = obj[fnName]
      obj[fnName] = (args...) ->
        hint = null
        if index?
          hint = args[index]
          hint = hint[field] if hint and field?
          if typeof hint == 'object'
            hint =
              if hint.constructor.name == 'Array'
                '[' + hint.join(', ') + ']'
              else
                hint.constructor.name
        hint = if hint? then "(#{hint})" else ''
        className = @constructor.__name ? @constructor.name
        pr.timer "#{className}::#{fnName}#{hint}", =>
          origFn.apply(this, args)


    onCurrentTimerFinish: (cb) ->
      ###
      Sets finish callback to the currently active profiler timer
      @param Function cb
      ###
      zone.timer().onFinish = cb


    getCompletedRootTimers: ->
      timersById[0].children.filter (t) -> t.finished



  # fake parent timer for all root timers (helpful to avoid code duplication)
  timersById[0] =
    childCompleteCounter: 0
    children: []

    addChild: (child) ->
      @children.push(child)
      @childCompleteCounter++

    completeChild: (child) ->
      @childCompleteCounter--



  class ProfilingTimer
    ###
    Represents profiling node that aims to account synchronous and asynchronous timing of execution.
    Timers organizes hierarchy. All timers created during execution of current timer (including async calls)
     are by default child timers of current timer. Exception - when timer is explicitly declared as root-level timer.
    ###

    startTime: 0
    asyncDetected: false
    syncTime: 0
    asyncTime: 0
    ownAsyncTime: 0
    error: null
    finished: false
    onFinish: null
    counter: 0
    ownTaskCount: 0
    clearTaskCount: 0
    waitDeps: null

    childCompleteCounter: 0
    children: null

    relativeStartTime: 0


    constructor: (@id, @name, @parentId) ->
      @children = []
      @waitDeps = []
      if @parentId == 0
        # it's important to use rootZone's setTimeout here to avoid including it to the context timer's zone
        @_zoneTimeoutId = rootZone.setTimeout =>
          console.warn 'Timer zone timed out!', this.name
          pr.emit('root-timer.timeout', this)
        , 25000
      @parent().addChild(this)
      @relativeStartTime = fixTimer() if @parentId == 0


    addChild: (child) ->
      @children.push(child)
      @childCompleteCounter++
      child.relativeStartTime = @relativeStartTime


    completeChild: (child) ->
      @childCompleteCounter--
      @complete() if @childCompleteCounter == 0 and @counter == 0


    complete: ->
      @asyncTime = 0 if not @asyncDetected
      @finished = true
      rootZone.clearTimeout(@_zoneTimeoutId)
      delete @_zoneTimeoutId
      @onFinish?(this)
      pr.emit('root-timer.complete', this) if @parentId == 0
      @parent().completeChild(this)


    parent: ->
      timersById[@parentId]


    toJSON: ->
      result =
        id: @id
        name: @name
        startTime: @startTime
        syncTime: @syncTime
        ownTaskCount: @ownTaskCount
        clearTaskCount: @clearTaskCount
        waitDeps: @waitDeps
      result.asyncTime = @asyncTime if @asyncTime > 0 and @finished
      result.ownAsyncTime = @ownAsyncTime
      if not @finished
        result.finished = @finished
        result.counter = @counter
        result.childCompleteCounter = @childCompleteCounter if @children.length > 0
      result.children = @children if @children.length > 0
      result



  # private functions

  ###
  Function to fix time intervals between two calls.
  @param (optional)Float startValue start time
  @return Float number of milliseconds between start time and current time
  ###
  fixTimer =
    if typeof process != 'undefined' and process.hrtime
      (startValue = 0) ->
        x = process.hrtime()
        (x[0] * 1e9 + x[1]) / 1e6 - startValue
    else
      nowFn =
        if window? and window.performance
          window.performance.now.bind(performance)
        else
          Date.now.bind(Date)
      (startValue = 0) ->
        nowFn() - startValue



  pr

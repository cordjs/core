define [
  'zone' + (if document? then '' else '.js')
  'cord!Api'
], (rootZone, Api) ->

  # zone-patching of cordjs higher-level functions which use asynchronous unpatched nodejs operations
  rootZone.constructor.patchFnWithCallbacks Api.prototype, [
    'send'
  ]

  # profiler-patch of the Api:send() method
  # TODO: do this using pr.patch()
  origApiSend = Api.prototype.send
  Api.prototype.send = (args...) ->
    pr.timer "Api::#{args[0]}(#{args[1]})", =>
      origApiSend.apply(this, args)


  # private vars

  # index of all timers by id
  timersById = {}
  # timers id generator
  timerIdCounter = 1

  currentTimer = null



  # Profiling zone

  profilerRootZone = rootZone.fork
    enqueueTask: ->
      @timer().asyncDetected = true
      @timer().counter++

    dequeueTask: ->
      @timer().counter--

    beforeTask: ->
      @timer().counter++

    afterTask: ->
      timer = @timer()
      timer.counter--
      if timer.counter == 0
        if timer.asyncDetected
          timer.asyncTime = fixTimer(timer.asyncTime)
        timer.complete() if timer.childCompleteCounter == 0

    onError: (err) ->
      console.log 'onError', name, @timer().counter, err
      @timer().error = err
      throw err

    timer: -> timersById[@timerId]

    timerId: 0



  # fake parent timer for all root timers (helpful to avoid code duplication)
  timersById[0] =
    childCompleteCounter: 0
    children: []

    addChild: (child) ->
      @children.push(child)
      @childCompleteCounter++

    completeChild: (child) ->
      @childCompleteCounter--
      pr.printTimer(child)


  pr =

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
      oldTimer = currentTimer
      timersById[timerId] = timer = currentTimer = new ProfilingTimer(name, myZone.timerId)

      myZone.fork
        timerId: timerId
      .run ->
        start = fixTimer()
        result = fn()
        timer.syncTime = fixTimer(start)
        timer.asyncTime = fixTimer()

        currentTimer = oldTimer

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


    onCurrentTimerFinish: (fn) ->
      currentTimer.onFinish = fn if currentTimer?


    printTimer: (timer) ->
      console.log '-------------------------------------------------'
      console.log 'Timer', timer.name
      console.log JSON.stringify(timer, null, 2)



  class ProfilingTimer
    ###
    Represents profiling node that aims to account synchronous and asynchronous timing of execution.
    Timers organizes hierarchy. All timers created during execution of current timer (including async calls)
     are by default child timers of current timer. Exception - when timer is explicitly declared as root-level timer.
    ###

    asyncDetected: false
    syncTime: 0
    asyncTime: 0
    error: null
    finished: false
    onFinish: null
    counter: 0

    childCompleteCounter: 0
    children: null


    constructor: (@name, @parentId) ->
      @children = []
      @_zoneTimeoutId = rootZone.setTimeout =>
        console.log '!!!!!!!===============================!!!!!!!'
        console.log 'Timer zone timed out!'
        pr.printTimer(this)
      , 15000
      @parent().addChild(this)


    addChild: (child) ->
      @children.push(child)
      @childCompleteCounter++


    completeChild: (child) ->
      @childCompleteCounter--
      @complete() if @childCompleteCounter == 0 and @counter == 0


    complete: ->
      @asyncTime = 0 if not @asyncDetected
      @finished = true
      rootZone.clearTimeout(@_zoneTimeoutId)
      delete @_zoneTimeoutId
      @parent().completeChild(this)


    parent: ->
      timersById[@parentId]



  # private functions

  ###
  Function to fix time intervals between two calls.
  @param (optional)Float startValue start time
  @return Float number of milliseconds between start time and current time
  ###
  fixTimer =
    if process and process.hrtime
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

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
  # list of root-level timers
  timers = []
  timersById = {}
  timerIdCounter = 0

  currentTimer = null

  pr =

    newRoot: (name, fn) ->
      result = undefined

      timerId = timerIdCounter++
      oldTimer = currentTimer
      timersById[timerId] = timer = currentTimer =
        name: name
        asyncDetected: false
        syncTime: 0
        asyncTime: 0
        error: null
        finished: false
        onFinish: null
        counter: 0

        childCompleteCounter: 0
        children: []

        addChild: (child) ->
          @children.push(child)
          @childCompleteCounter++

        completeChild: (child) ->
          @childCompleteCounter--
          if @childCompleteCounter == 0 and @counter == 0
            @asyncTime = 0 if not @asyncDetected
            @finished = true
            @onFinish?(timer)

      timers.push(timer)

      timer.zoneTimeoutId = rootZone.setTimeout ->
        console.log '!!!!!!!===============================!!!!!!!'
        console.log 'Root timer zone timed out!'
        pr.saveTimer(timer)
      , 9000

      rootZone.fork
        enqueueTask: ->
          timer.asyncDetected = true
          timer.counter++

        dequeueTask: ->
          timer.counter--

        afterTask: ->
          if timer.counter == 0
            if timer.asyncDetected
              timer.asyncTime = fixTimer(timer.asyncTime)
            if timer.childCompleteCounter == 0
              timer.asyncTime = 0 if not timer.asyncDetected
              timer.finished = true
              timer.onFinish?(timer)

        onError: (err) ->
          timer.error = err
          throw err

        timerId: timerId

      .run ->
        start = fixTimer()
        result = fn()
        timer.syncTime = fixTimer(start)
        timer.asyncTime = fixTimer()

        currentTimer = oldTimer

        result


    timer: (name, fn) ->
      ###
      Creates a new timer with the given name and calls and profiles the given function "inside" of that timer.
      @param String name timer name
      @param Function fn the profiled function
      @return Any the profiled function's return value
      ###
      result = undefined

      timerId = timerIdCounter++
      oldTimer = currentTimer
      timersById[timerId] = timer = currentTimer =
        name: name
        asyncDetected: false
        syncTime: 0
        asyncTime: 0
        error: null
        finished: false
        onFinish: null
        counter: 0

        childCompleteCounter: 0
        children: []

        addChild: (child) ->
          @children.push(child)
          @childCompleteCounter++

        completeChild: (child) ->
          @childCompleteCounter--
          if @childCompleteCounter == 0 and @counter == 0
            @asyncTime = 0 if not @asyncDetected
            @finished = true
            parentTimer.completeChild(this)

      parentTimer = timersById[zone.timerId]
      parentTimer.addChild(timer)

      zone.fork
        enqueueTask: ->
          timer.asyncDetected = true
          timer.counter++

        dequeueTask: ->
          timer.counter--

        afterTask: ->
          if timer.counter == 0
            if timer.asyncDetected
              timer.asyncTime = fixTimer(timer.asyncTime)
            if timer.childCompleteCounter == 0
              timer.asyncTime = 0 if not timer.asyncDetected
              timer.finished = true
              parentTimer.completeChild(timer)

        onError: (err) ->
          console.log 'onError', name, timer.counter, err
          timer.error = err
          throw err

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


    saveTimer: (timer) ->
      if timer.zoneTimeoutId?
        clearTimeout(timer.zoneTimeoutId)
        delete timer.zoneTimeoutId
      console.log '-------------------------------------------------'
      console.log 'Fake saving timer', timer.name
      console.log JSON.stringify(timer, null, 2)



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

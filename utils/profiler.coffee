define [
  'zone' + (if document? then '' else '.js')
], (zone) ->

  rootZone = zone

  # private vars
  timers = {}

  pr =

    newRoot: (name, fn) ->
      result = undefined
      asyncStart = undefined

      currentTimer =
        name: name
        children: []
      timers.push(currentTimer)

      rootZone.fork
        '+enqueueTask': ->
        '-dequeueTask': ->
        '+afterTask': ->
        data:
          count: 0
      .run ->
        @name = name
        zone.data.currentProfilerTimer = currentTimer
        start = timer()
        result = fn()
        currentTimer.syncTime = timer(start)
        asyncStart = timer()
        result
      .setCallback (err) ->
        currentTimer.asyncTime = timer(asyncStart)
        currentTimer.asyncErr = err if err

      result


    timer: (name, fn) ->
      result = undefined
      asyncStart = undefined

      currentTimer =
        name: name
        children: []
      zone.data.currentProfilerTimer.children.push(currentTimer)

      zone.create ->
        @name = name
        zone.data.currentProfilerTimer = currentTimer
        start = timer()
        result = fn()
        currentTimer.syncTime = timer(start)
        asyncStart = timer()
        result
      .setCallback (err) ->
        currentTimer.asyncTime = timer(asyncStart)
        currentTimer.asyncErr = err if err

      result



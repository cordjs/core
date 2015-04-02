define [
  'underscore'
  'cord!utils/Defer'
], (_, Defer) ->

  # unhandled tracking settings
  unhandledTrackingEnabled = false
  unhandledSoftTracking = false
  unhandledMap = null

  logOriginStackTrace = !!global.config?.debug.future.logOriginStackTrace

  # environment-dependent console object
  cons = -> if typeof _console != 'undefined' then _console else console

  class Future
    ###
    Home-grown promise implementation (reinvented the wheel)
    ###

    _counter: 0
    _doneCallbacks: null
    _failCallbacks: null
    _alwaysCallbacks: null
    _order: 0
    _callbackArgs: null

    _locked: false
    # completed by any way
    _completed: false
    # current state: pending, resolved or rejected
    _state: 'pending'

    # helpful to identify the future during debugging
    _name: ''

    # timeout for uncompleted futures
    _incompleteTimeout: null


    constructor: (initialCounter = 0, name = ':noname:') ->
      ###
      @param (optional)Int initialCounter initial state of counter, syntax sugar to avoid (new Future).fork().fork()
      @param (optional)String name individual name of the future to separate it from others during debugging
      ###
      if initialCounter? and _.isString(initialCounter)
        name = initialCounter
        initialCounter = 0
      @_counter = initialCounter
      @_doneCallbacks = []
      @_failCallbacks = []
      @_alwaysCallbacks = []
      @_name = name

      if logOriginStackTrace
        @_stack = (new Error).stack

      @_initDebugTimeout() if @_counter > 0
      @_initUnhandledTracking() if unhandledTrackingEnabled


    name: (nameSuffix) ->
      ###
      Appends name suffix to this promise's name. Useful for debugging when there is no API to set name another way.
      Returns this promise, so can be used in call-chains.
      @param {String} nameSuffix
      @return {Future} this
      ###
      if @_name == '' or @_name == ':noname:'
        @_name = nameSuffix
      else
        @_name += " [#{nameSuffix}]"
      this


    rename: (name) ->
      ###
      Renames current future
      ###
      @_name = name
      this


    fork: ->
      ###
      Adds one more value to wait.
      Should be paired with following resolve() call.
      @return Future(self)
      ###
      if @_completed and not (@_state == 'rejected' and @_counter > 0)
        throw new Error("Trying to use the completed future [#{@_name}]!")
      throw new Error("Trying to fork locked future [#{@_name}]!") if @_locked
      @_counter++
      @_initDebugTimeout() if @_counter == 1
      this


    resolve: (args...) ->
      ###
      Indicates that one of the waiting values is ready.
      If there are some arguments passed then they are passed unchanged to the done-callbacks.
      If there is no value remaining in the aggregate and done method is already called
       than callback is fired immediately.
      Should have according fork() call before.
      ###
      if @_counter > 0
        @_counter--
        if @_state != 'rejected'
          @_callbackArgs = [args] if args.length > 0
          if @_counter == 0
            # For the cases when there is no done function
            @_state = 'resolved' if @_locked
            @_clearUnhandledTracking() if unhandledSoftTracking and @_locked
            @_runDoneCallbacks() if @_doneCallbacks.length > 0
            @_runAlwaysCallbacks() if @_alwaysCallbacks.length > 0
            @_clearFailCallbacks() if @_state == 'resolved'
            @_clearDebugTimeout()
          # not changing state to 'resolved' here because it is possible to call fork() again if done hasn't called yet
      else
        nameStr = if @_name then " (name = #{@_name})" else ''
        throw new Error(
          "Future::resolve() is called more times than Future::fork!#{nameStr} state = #{@_state}, [#{@_callbackArgs}]"
        )

      this


    reject: (err) ->
      ###
      Indicates that the promise is rejected (failed) and fail-callbacks should be called.
      If there are some arguments passed then they are passed unchanged to the fail-callbacks.
      If fail-method is already called than callbacks are fired immediately, otherwise they'll be fired
       when fail-method is called.
      Only first call of this method is important. Any subsequent calls does nothing but decrementing the counter.
      ###
      if @_counter > 0
        @_counter--
        if @_state != 'rejected'
          @_state = 'rejected'
          @_callbackArgs = [err ? new Error("Future[#{@_name}] rejected without error message!")]
          @_runFailCallbacks() if @_failCallbacks.length > 0
          @_runAlwaysCallbacks() if @_alwaysCallbacks.length > 0
          @_clearDoneCallbacks()
          @_clearDebugTimeout()
      else
        throw new Error(
          "Future::reject is called more times than Future::fork! [#{@_name}], state = #{@_state}, [#{@_callbackArgs}]"
        )

      this


    complete: (err, args...) ->
      ###
      Completes this promise either with successful of failure result depending on the arguments.
      If first argument is not null than the promise is completed with reject using first argument as an error.
      Otherwise remaining arguments are used for promise.resolve() call.
      This method is useful to work with lots of APIs using such semantics of the callback agruments.
      ###
      if err?
        @reject(err)
      else
        @resolve.apply(this, args)


    when: ->
      ###
      Adds another future(promise)(s) as a condition of completion of this future
      Can be called multiple times.
      @param (variable)Future args another future which'll be waited
      @return Future self
      @todo maybe need to support noTimeout property of futureList promises
      ###
      self = this
      for promise in arguments
        @fork() if not @_locked
        self.withoutTimeout()  if promise._noTimeout
        promise
          .done(-> self.resolve.apply(self, arguments))
          .fail(-> self.reject.apply(self, arguments))
      this


    link: (anotherPromise) ->
      ###
      Inversion of `when` method. Tells that the given future will complete when this future will complete.
      Just syntax sugar to convert anotherFuture.when(future) to future.link(anotherFuture).
      In some cases using link instead of when leads to more elegant code.
      @param Future anotherFuture
      @return Future self
      ###
      anotherPromise.when(this)
      this


    done: (callback) ->
      ###
      Defines callback function to be called when future is resolved.
      If all waiting values are already resolved then callback is fired immedialtely.
      If done method is called several times than all passed functions will be called.
      ###
      if @_state != 'rejected'
        @_doneCallbacks.push(callback)
        if @_counter == 0
          @_clearDebugTimeout()
          Defer.nextTick =>
            @_runDoneCallbacks()
            @_clearFailCallbacks()
      this


    fail: (callback) ->
      ###
      Defines callback function to be called when future is rejected.
      If all waiting values are already resolved then callback is fired immedialtely.
      If fail method is called several times than all passed functions will be called.
      ###
      throw new Error("Invalid argument for Future.fail(): #{ callback }. [#{@_name}]") if not _.isFunction(callback)
      if @_state != 'resolved'
        @_failCallbacks.push(callback)
        if @_state == 'rejected'
          @_clearDebugTimeout()
          Defer.nextTick =>
            @_runFailCallbacks()
      @_clearUnhandledTracking() if unhandledTrackingEnabled
      this


    finally: (callback) ->
      ###
      Defines callback function to be called when future is completed by any mean.
      Callback arguments are using popular semantics with first-argument-as-an-error (Left) and other arguments
       are successful results of the future.
      ###
      @_alwaysCallbacks.push(callback)
      if @_counter == 0 or @_state == 'rejected'
        @_clearDebugTimeout()
        Defer.nextTick =>
          @_runAlwaysCallbacks()
          @_clearFailCallbacks() if @_state == 'resolved'
      @_clearUnhandledTracking() if unhandledTrackingEnabled
      this


    failAloud: (message) ->
      ###
      Adds often-used scenario of fail that just loudly reports the error
      ###
      name = @_name
      @fail (err) =>
        reportArgs = ["Future(#{name})::failAloud#{ if message then " with message: #{message}" else '' }", err]
        if @_stack
          reportArgs.push("\n---------------\n")
          reportArgs.push(@_stack)
        cons().error.apply(cons(), reportArgs)


    failOk: ->
      ###
      Registers empty fail handler for the Future to prevent it to be reported in unhandled failure tracking.
      This method is useful when the failure result is expected and it's OK not to handle it.
      ###
      @fail(_.noop)


    callback: (neededArgs...) ->
      ###
      Generates callback proxy function to be used in return-in-async-callback functions
       which allows to avoid callback-indentation hell by merging callback callback calls
       of several such functions into one callback which is called when all async functions
       are complete.

      All arguments of aggregated callbacks are passed to 'done'-defined callback in order of calling
       'callback' method.

      @see example 2 in class documentation block
      ###
      @fork()
      order = @_order++
      @_callbackArgs ?= {}
      (args...) =>
        if @_state != 'rejected'
          if neededArgs.length
            result = []
            for i in neededArgs
              result.push args[i]
          else
            result = args
          @_callbackArgs[order] = result
        @resolve()


    completed: ->
      ###
      Indicates that callbacks() are already called at least once and fork() cannot be called anymore
      @return Boolean
      ###
      @_completed = true if not @_completed and @_counter == 0
      @_completed


    pending: ->
      ###
      Indicates, that current Future now in pending state
      Syntax sugar for state() == 'pending'
      ###
      @state() == 'pending'


    state: ->
      ###
      Returns state of the promise - 'pending', 'resolved' or 'rejected'
      @return String
      ###
      @_state


    lock: ->
      @_locked = true
      this


    then: (onResolved, onRejected, _nameSuffix = 'then') ->
      ###
      Implements 'then'-semantics to be compatible with standard JS Promise.
      Both arguments are optional but at least on of them must be defined!
      @param (optional)Function onResolved callback to be evaluated in case of successful resolving of the promise
                                           This is the same as using of combination of map() or flatMap()
                                           (depending of the callback's returned type).
                                           If the Future returned then it's result is proxied to the then-result Future.
                                           Returned Array is spread into same number of callback arguments.
                                           If exception is thrown then it's wrapped into rejected Future and returned.
                                           Any other return value is just returned wrappend into resulting Future.
      @param (optional)Function onRejected callback to be evaluated in case of the promise rejection
                                           This is the same as using catch() method.
                                           Return value behaviour is the same as for `onResolved` callback
      @return Future[A]
      ###
      if not onResolved? and not onRejected?
        _nameSuffix = 'then(empty)'
      result = Future.single("#{@_name} -> #{_nameSuffix}")
      result.withoutTimeout() if @_noTimeout
      if onResolved?
        @done ->
          try
            res = onResolved.apply(null, arguments)
            if res instanceof Future
              result.when(res)
            else if _.isArray(res)
              result.resolve.apply(result, res)
            else
              result.resolve(res)
          catch err
            if result.completed()
              throw err
            else
              result.reject(err)
      else
        @done -> result.resolve.apply(result, arguments)
      if onRejected?
        @fail (err) ->
          try
            res = onRejected.call(null, err)
            if res instanceof Future
              result.when(res)
            else if _.isArray(res)
              result.resolve.apply(result, res)
            else
              result.resolve(res)
          catch err1
            if result.completed()
              throw err1
            else
              result.reject(err1)
      else
        @fail (err) -> result.reject(err)
      result


    catch: (callback) ->
      ###
      Implements 'catch'-semantics to be compatible with standard JS Promise.
      Shortcut for promise.then(undefined, callback)
      @see then()
      @param Function callback function to be evaluated in case of the promise rejection
      @return Future[A]
      ###
      this.then(undefined, callback, 'catch')


    catchIf: (predicate, callback) ->
      ###
      Catch error only if predicate returns true. On catch calls callback, if specified.
      If predicate instance of Error, then error catched only of error instanceof predicate
      @param Function predicate
      @return Future
      ###

      if predicate instanceof Error
        do (errorClass = predicate) =>
          predicate = (e) -> e instanceof errorClass

      this.catch (err) ->
        if predicate(err)
          callback?(err)
        else
          throw err


    spread: (onResolved, onRejected) ->
      ###
      Like then but expands Array result of the Future to the multiple arguments of the onResolved function call.
      ###
      this.then (array) ->
        onResolved.apply(null, array)
      , onRejected


    map: (callback) ->
      ###
      Creates new Future by applying the given callback to the successful result of this Future.
      Resolves resulting future with the result of the callback.
      If callback returns an Array than it's considered as a list of results. If it is necessary to return a single
       array than callback must return an Array with single item containing the resulting Array (Array in Array).
      If this Future is rejected than the resulting Future will contain the same error.
      ###
      result = Future.single("#{@_name} -> map")
      result.withoutTimeout() if @_noTimeout
      @done ->
        try
          mapRes = callback.apply(null, arguments)
          if _.isArray(mapRes)
            result.resolve.apply(result, mapRes)
          else
            result.resolve(mapRes)
        catch err
          if result.completed()
            throw err
          else
            result.reject(err)
      @fail (err) -> result.reject(err)
      result


    flatMap: (callback) ->
      ###
      Creates new Future by applying the given callback to the successful result of this Future.
      Returns result of the callback as a new Future.
      Callback must return a Future, and resulting Future is completed when the callback-returned future is completed.
      If this Future is rejected than the resulting Future will contain the same error.
      @param Function(this.result -> Future(A)) callback
      @return Future(A)
      ###
      result = Future.single("#{@_name} -> flatMap")
      result.withoutTimeout() if @_noTimeout
      @done ->
        try
          result.when(callback.apply(null, arguments))
        catch err
          if result.completed()
            throw err
          else
            result.reject(err)
      @fail (err) -> result.reject(err)
      result


    andThen: (callback) ->
      ###
      Creates and returns a new future with the same result as this future but completed only after invoking
       of the given callback-function. Callback is called on any result of the future.
      Arguments of the callback has the same meaning as always()-callbacks.
      This method allows for establishing order of callbacks.
      @param Function(err, results...) callback
      @return Future(this.result)
      ###
      result = Future.single("#{@_name} -> andThen")
      result.withoutTimeout() if @_noTimeout
      this.finally ->
        callback.apply(null, arguments)
        result.complete.apply(result, arguments)
      result


    zip: (those...) ->
      ###
      Zips the values of this and that future, and creates a new future holding the tuple of their results.
      If some of the futures have several results that they are represented as array, not "flattened".
      No result represented as undefined value.
      @param Future those another futures
      @return Future
      ###
      those.unshift(this)
      Future.sequence(those, "#{@_name} -> zip").map (result) -> result


    @sequence: (futureList, name = ':sequence:') ->
      ###
      Converts Array[Future[X]] to Future[Array[X]]
      @todo maybe need to support noTimeout property of futureList promises
      ###
      promise = new Future(name)
      result = []
      for f, i in futureList
        do (i) ->
          promise.fork()
          f.done (res...) ->
            result[i] = switch res.length
              when 1 then res[0]
              when 0 then undefined
              else res
            promise.resolve()
          .fail (e) ->
            promise.reject(e)
      promise.map -> [result]


    @select: (futureList) ->
      ###
      Returns new future which completes successfully when one of the given futures completes successfully (which comes
       first). Resulting future resolves with that first-completed future's result. All subsequent completing
       futures are ignored.
      Result completes with failure if all of the given futures fails.
      @param Array[Future[X]] futureList
      @return Future[X]
      @todo maybe need to support noTimeout property of futureList promises
      ###
      result = @single(':select:')
      ready = false
      failCounter = futureList.length
      for f in futureList
        do (f) ->
          f.done ->
            if not ready
              result.when(f)
              ready = true
          .fail ->
            failCounter--
            if failCounter == 0
              result.reject("All selecting futures have failed!")
      result


    _runDoneCallbacks: ->
      ###
      Fires resulting callback functions defined by done with right list of arguments.
      ###
      @_state = 'resolved'
      @_clearUnhandledTracking() if unhandledSoftTracking and not @_locked
      # this is need to avoid duplicate callback calling in case of recursive coming here from callback function
      callbacksCopy = @_doneCallbacks
      @_doneCallbacks = []
      @_runCallbacks(callbacksCopy, true)


    _runFailCallbacks: ->
      ###
      Fires resulting callback functions defined by fail with right list of arguments.
      ###
      # this is need to avoid duplicate callback calling in case of recursive coming here from callback function
      callbacksCopy = @_failCallbacks
      @_failCallbacks = []
      @_runCallbacks(callbacksCopy)


    _runAlwaysCallbacks: ->
      ###
      Fires resulting callback functions defined by always with right list of arguments.
      ###
      @_state = 'resolved' if @_state == 'pending'
      callbacksCopy = @_alwaysCallbacks
      @_alwaysCallbacks = []
      @_completed = true

      args = []
      if @_state == 'resolved'
        # for successfully completed future we must add null-error first argument.
        args.push(null)
        if @_callbackArgs?
          len = if @_order > 0 then @_order else @_callbackArgs.length
          for i in [0..len-1]
            args = args.concat(@_callbackArgs[i])
      else
        # for rejected future there is no need to flatten argument as there is only one error.
        args = @_callbackArgs

      callback.apply(null, args) for callback in callbacksCopy


    _runCallbacks: (callbacks, flattenArgs = false) ->
      ###
      Helper-method to run list of callbacks.
      @param Array(Function) callbacks
      ###
      @_completed = true

      if @_callbackArgs?
        args = []
        if flattenArgs
          len = if @_order > 0 then @_order else @_callbackArgs.length
          for i in [0..len-1]
            args = args.concat(@_callbackArgs[i])
        else
          args = @_callbackArgs
        callback.apply(null, args) for callback in callbacks
      else
        callback() for callback in callbacks


    # syntax-sugar constructors

    @single: (name = ':single:') ->
      ###
      Returns the future, which can not be forked and must be resolved by only single call of resolve().
      @return Future
      ###
      (new Future(1, name)).lock()


    @resolved: ->
      ###
      Returns the future already resolved with the given arguments.
      @return Future
      ###
      result = @single(':resolved:')
      result.resolve.apply(result, arguments)
      result


    @rejected: (error) ->
      ###
      Returns the future already rejected with the given error
      @param Any error
      @return Future
      ###
      result = @single(':rejected:')
      result.reject(error)
      result


    @call: (fn, args...) ->
      ###
      Converts node-style function call with last-agrument-callback result to pretty composable future-result call.
      Node-style callback mean Function[err, A] - first argument if not-null means error and converts to
       Future.reject(), all subsequent arguments are treated as a successful result and passed to Future.resolve().
      Example:
        Traditional style:
          fs.readFile '/tmp/file', (err, data) ->
            throw err if err
            // do something with data
        Future-style:
          Future.call(fs.readFile, '/tmp/file').failAloud().done (data) ->
            // do something with data
      @param Function|Tuple[Object, String] fn callback-style function to be called (e.g. fs.readFile)
      @param Any args* arguments of that function without last callback-result argument.
      @return Future[A]
      ###
      result = @single(":call:(#{fn.name})")
      args.push ->
        result.complete.apply(result, arguments) if not result.completed()
      try
        if _.isArray(fn)
          fn[0][fn[1]].apply(fn[0], args)
        else
          fn.apply(null, args)
      catch err
        result.reject(err) if not result.completed()
      result


    @timeout: (millisec) ->
      ###
      Returns the future wich will complete after the given number of milliseconds
      @param Int millisec number of millis before resolving the future
      @return Future
      ###
      result = @single(":timeout:(#{millisec})")
      setTimeout ->
        result.resolve()
      , millisec
      result


    @require: (paths...) ->
      ###
      Convenient Future-wrapper for requirejs's require call.
      @param String* paths list of modules requirejs-format paths
      @return Future(modules...)
      ###
      paths = paths[0] if paths.length == 1 and _.isArray(paths[0])
      result = @single(':require:('+ paths.join(', ') + ')')
      require paths, ->
        try
          result.resolve.apply(result, arguments)
        catch err
          # this catch is needed to prevent require's error callbacks to fire when error is caused
          # by th result's callbacks. Otherwise we'll try to reject already resolved promise two lines below.
          cons().error "Got exception in Future.require() callbacks for [#{result._name}]:", err
      , (err) ->
        result.reject(err)
      result


    @try: (fn) ->
      ###
      Wraps synchronous function result into resolved or rejected Future depending if the function throws an exception
      @param Function fn function to be called
      @return Future if the argument function throws exception than Future.rejected with that exception is returned
                     if the argument function returns a Future than it is returned as-is
                     otherwise Future.resolved with the function result is returned
      ###
      try
        res = fn()
        if res instanceof Future
          res
        else
          Future.resolved(res)
      catch err
        Future.rejected(err)


    withoutTimeout: ->
      ###
      Mark that Future's normal behaviour is to wait forever
      For instance a Future that depends on user's input
      ###
      @_clearDebugTimeout()
      @_noTimeout = true
      this



    _initDebugTimeout: ->
      timeout = global.config?.debug.future.timeout
      if timeout > 0 and @_name.indexOf('_shownPromise') < 0 and @_name.indexOf('_widgetReadyPromise') < 0
        @_incompleteTimeout = setTimeout =>
          if @state() == 'pending' and @_counter > 0
            reportArgs = ["Future timed out [#{@_name}] (#{timeout/1000} seconds), counter = #{@_counter}"]
            reportArgs.push(@_stack)  if @_stack
            cons().warn.apply(cons(), reportArgs)
        , timeout


    _clearDebugTimeout: ->
      if @_incompleteTimeout?
        clearTimeout(@_incompleteTimeout)
        @_incompleteTimeout = null


    _clearDoneCallbacks: ->
      @_doneCallbacks = []


    _clearFailCallbacks: ->
      @_failCallbacks = []


    clear: ->
      ###
      Way to eliminate any impact of resolving or rejecting or time-outing of this promise.
      Should be used when actions that are waiting for this promise completion are no more needed.
      ###
      @_clearDoneCallbacks()
      @_clearFailCallbacks()
      @_alwaysCallbacks = []
      @_clearDebugTimeout()
      @_clearUnhandledTracking() if unhandledTrackingEnabled


    # debugging

    _initUnhandledTracking: ->
      ###
      Registers the promise to the unhandled failure tracking map.
      ###
      @_trackId = _.uniqueId()
      unhandledMap[@_trackId] =
        startTime: (new Date).getTime()
        promise: this


    _clearUnhandledTracking: ->
      ###
      Removes the promise from the unhandled failure tracking map.
      Should be called when failure handling callback is registered.
      ###
      delete unhandledMap[@_trackId]


    _debug: (args...) ->
      ###
      Debug logging method, which logs future's name, counter, callback length, and given arguments.
      Can emphasise futures with desired names by using console.warn.
      ###
      if @_name.indexOf('desired search in name') != -1
        fn = cons().warn
      else
        fn = cons().log
      args.unshift(@_name)
      args.unshift(@_doneCallbacks.length)
      args.unshift(@_counter)
      fn.apply(cons, args)



  initUnhandledTracker = ->
    ###
    Initializes infinite checking of promises with unhandled failure result.
    ###
    unhandledSoftTracking = !!global.config?.debug.future.trackUnhandled.soft
    interval = parseInt(global.config?.debug.future.trackUnhandled.interval)
    timeout = parseInt(global.config?.debug.future.trackUnhandled.timeout)
    unhandledMap = {}
    if interval > 0
      setInterval =>
        curTime = (new Date).getTime()
        for id, info of unhandledMap
          if curTime - info.startTime > timeout
            state = info.promise.state()
            if state != 'pending'
              reportArgs = [
                "Unhandled rejection detected for Future[#{info.promise._name}] " +
                  "after #{(curTime - info.startTime) / 1000 } seconds!"
                state
              ]
              if state == 'rejected'
                err = info.promise._callbackArgs[0]
                reportArgs.push(err)
                reportArgs.push(err.stack) if err.stack
                if info.promise._stack
                  reportArgs.push("\n--------------------------\n")
                  reportArgs.push(info.promise._stack)
                cons().warn.apply(cons(), reportArgs)
            delete unhandledMap[id]
      , interval


  unhandledTrackingEnabled = !!global.config?.debug.future.trackUnhandled.enable
  initUnhandledTracker() if unhandledTrackingEnabled


  Future

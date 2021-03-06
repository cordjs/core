define [
  'underscore'
  './asapInContext'
], (_, asapInContext) ->

  # unhandled tracking settings
  unhandledTrackingEnabled = false
  unhandledSoftTracking = false
  unhandledMap = null

  unresolvedTrackingEnabled = false
  unresolvedMap = null

  longStackTraceEnabled = false
  # mutable global context promise changed before and after `then` callback processing
  # to properly detect "parent" promise for long stack-traces
  currentContextPromise = null

  # environment-dependent console object
  cons = -> if typeof _console != 'undefined' then _console else console

  class FutureInspection
    ###
    Special helper class for synchronous inspection of given future
    ###

    constructor: (@future) ->


    isResolved: ->
      ###
      Part of the FutureInspection interface
      Is inspected Future resolved
      @return {Boolean}
      ###
      @future.isResolved()


    isPending: ->
      ###
      Part of the FutureInspection interface
      Is inspected Future pending
      @return {Boolean}
      ###
      @future.isPending()


    isRejected: ->
      ###
      Part of the FutureInspection interface
      Is inspected Future rejected
      @return {Boolean}
      ###
      @future.isRejected()


    value: ->
      ###
      Part of the FutureInspection interface.
      Returns resolve value of Future.
      Throws an error if future is not resolved. You should check method `isResolved` firstly.
      @return {*}
      ###
      @future.value()


    reason: ->
      ###
      Part of the FutureInspection interface.
      Returns rejection reason of Future.
      Throws an error if future is not rejected. You should check method `isRejected` firstly.
      @return {Error}
      ###
      @future.reason()


  class Future
    ###
    Home-grown promise implementation (reinvented the wheel)
    ###

    _counter: 0
    _doneCallbacks: null
    _failCallbacks: null
    _settledValue: undefined

    _locked: false
    # completed by any way
    _completed: false
    # current state: pending, resolved or rejected
    _state: 'pending'

    # helpful to identify the future during debugging
    _name: ''

    # parent promise. Set according to `then` callback context when promise is created
    _parent: null

    # context object (this) for the promise callbacks set using `bind` method
    _boundTo: undefined


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
      @_name = name

      if longStackTraceEnabled
        try
          throw new Error()
        catch e
          error = e
        @_stack = error.stack
        # defining 'parent' promise as a promise whose `then` callback execution created this promise
        # used to construct beautiful long stack trace
        @_parent = currentContextPromise  if currentContextPromise

      @_initDebugTimeout() if unresolvedTrackingEnabled
      @_initUnhandledTracking() if unhandledTrackingEnabled


    nameSuffix: (nameSuffix) ->
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


    name: (nameSuffix) ->
      ###
      Support old notation
      ###
      console.trace 'DEPRECATION WARNING: Future.name is deprecated, use .rename() ir .nameSuffix() instead'
      @nameSuffix(nameSuffix)


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
      this


    resolve: (value) ->
      ###
      Indicates that one of the waiting values is ready.
      If there are some arguments passed then they are passed unchanged to the done-callbacks.
      If there is no value remaining in the aggregate and done method is already called
       than callback is fired immediately.
      Should have according fork() call before.
      ###
      if @_counter > 0
        if value instanceof Future
          promise = this
          value.then(
            (r) ->
              promise.resolve(r)
              return
            (e) ->
              promise.reject(e)
              return
          )
        else
          @_counter--
          if @_state != 'rejected' and @_doneCallbacks
            @_settledValue = value
            if @_counter == 0
              # For the cases when there is no done function
              @_state = 'resolved' if @_locked
              @_clearUnhandledTracking() if unhandledSoftTracking and @_locked
              @_runDoneCallbacks() if @_doneCallbacks.length > 0
              @_clearFailCallbacks() if @_state == 'resolved'
              @_clearDebugTimeout() if unresolvedTrackingEnabled
            # not changing state to 'resolved' here because it is possible to call fork() again if done hasn't called yet
      else
        nameStr = if @_name then " (name = #{@_name})" else ''
        throw new Error(
          "Future::resolve() is called more times than Future::fork!#{nameStr} state = #{@_state}, [#{@_settledValue}]"
        )

      this


    reject: (reason) ->
      ###
      Indicates that the promise is rejected (failed) and fail-callbacks should be called.
      If there are some arguments passed then they are passed unchanged to the fail-callbacks.
      If fail-method is already called than callbacks are fired immediately, otherwise they'll be fired
       when fail-method is called.
      Only first call of this method is important. Any subsequent calls does nothing but decrementing the counter.
      ###
      if @_counter > 0
        @_counter--
        if @_state != 'rejected' and @_failCallbacks  # empty failCallbacks means cleared (cancelled) promise
          @_state = 'rejected'
          @_settledValue = reason ? new Error("Future[#{@_name}] rejected without error message!")
          @_clearDoneCallbacks()
          @_runFailCallbacks() if @_failCallbacks.length > 0
          @_clearDebugTimeout() if unresolvedTrackingEnabled
      else
        throw new Error(
          "Future::reject is called more times than Future::fork! [#{@_name}], state = #{@_state}, [#{@_settledValue}]"
        )

      this


    complete: (err, value) ->
      ###
      Completes this promise either with successful of failure result depending on the arguments.
      If first argument is not null than the promise is completed with reject using first argument as an error.
      Otherwise remaining arguments are used for promise.resolve() call.
      This method is useful to work with lots of APIs using such semantics of the callback agruments.
      ###
      if err?
        @reject(err)
      else
        @resolve(value)


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
        self.withoutTimeout()  if promise._noTimeout or not global.config?.debug.future.trackInternalTimeouts
        promise
          ._done(@resolve, this)
          ._fail(@reject, this)
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
      @_done(callback, @_boundTo)


    _done: (cb, ctx, arg) ->
      ###
      Appends given callback to the resolved task queue and triggers its execution asynchronously if needed.
      @param {Function} cb - callback function to be called when the promise completes successfully
                             promise result value will be passed to the callback as a first argument
      @param {Object|null} ctx - optional context (this) object to be used for the callback
      @param {Any} arg - optional second argument to be passed to the callback function besides the promise result
      @return {Future} this promise (for chaining)
      ###
      if @_state != 'rejected' and @_doneCallbacks
        addCallbackToQueue(@_doneCallbacks, cb, ctx, arg)
        # queue length == 3 means that the above addition is the first task in the queue and the queue
        # is not in the process of execution (flushing) and it need to be triggered
        if @_counter == 0 and @_doneCallbacks.length == 3
          @_clearDebugTimeout()  if unresolvedTrackingEnabled
          asapInContext(this, asapDoneCb)
      this


    fail: (callback) ->
      ###
      Defines callback function to be called when future is rejected.
      If all waiting values are already resolved then callback is fired immedialtely.
      If fail method is called several times than all passed functions will be called.
      ###
      throw new Error("Invalid argument for Future.fail(): #{ callback }. [#{@_name}]") if not _.isFunction(callback)
      @_fail(callback, @_boundTo)


    _fail: (cb, ctx, arg) ->
      ###
      Appends given callback to the failed task queue and triggers its execution asynchronously if needed.
      @param {Function} cb - callback function to be called when the promise is rejected
                             promise's reject reason will be passed to the callback as a first argument
      @param {Object|null} ctx - optional context (this) object to be used for the callback
      @param {Any} arg - optional second argument to be passed to the callback function besides the promise result
      @return {Future} this promise (for chaining)
      ###
      if @_state != 'resolved' and @_failCallbacks
        addCallbackToQueue(@_failCallbacks, cb, ctx, arg)
        # queue length == 3 means that the above addition is the first task in the queue and the queue
        # is not in the process of execution (flushing) and it need to be triggered
        if @_state == 'rejected' and @_failCallbacks.length == 3
          @_clearDebugTimeout() if unresolvedTrackingEnabled
          asapInContext(this, asapFailCb)
      @_clearUnhandledTracking() if unhandledTrackingEnabled
      this


    finally: (callback) ->
      ###
      Defines callback function to be called when future is completed by any mean.
      Callback arguments are using popular semantics with first-argument-as-an-error (Left) and other arguments
       are successful results of the future.
      Returns a new promise completed with this promise result (successful or rejected) after the callback is executed.
      Unlike `then` the callback cannot modify the resulting value with one exception:
       if the callback throws error then the resulting promise is rejected with that error.
      @param {Function} callback
      @return {Future<Any>}
      ###
      result = Future.single("#{@_name} -> finally")
      result._boundTo = @_boundTo
      result.withoutTimeout()  if @_noTimeout or not global.config?.debug.future.trackInternalTimeouts
      @_done(finallyDoneCb, result, callback)
      @_fail(finallyFailCb, result, callback)
      @_clearUnhandledTracking() if unhandledTrackingEnabled and callback.length > 0
      result


    failAloud: (message) ->
      ###
      Adds often-used scenario of fail that just loudly reports the error
      ###
      @_fail(failAloudCb, this, message)


    failOk: ->
      ###
      Registers empty fail handler for the Future to prevent it to be reported in unhandled failure tracking.
      This method is useful when the failure result is expected and it's OK not to handle it.
      ###
      @_fail(_.noop)


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


    bind: (thisArg) ->
      ###
      Creates a promise that follows this promise, but is bound to the given thisArg value.
      A bound promise will call its handlers with the bound value set to this. Additionally promises derived
       from a bound promise will also be bound promises with the same thisArg binding as the original promise.
      If thisArg is a Future, its resolution will be awaited for and the bound value will be the promise's
       fulfillment value. If thisArg rejects then the returned promise is rejected with the thisArg's rejection reason.
      Note that this means you cannot use this without checking inside catch handlers for promises that bind to promise
       because in case of rejection of thisArg, this will be undefined
      @param {Object} thisArg
      @return {Future<thisFutureType>}
      ###
      result = Future.single("#{@_name} -> bind")
      if thisArg instanceof Future
        thisArg._done(bindResolvedCb, this, result)
        thisArg._fail(@reject, result)
      else
        result._boundTo = thisArg
        result.when(this)
      result


    then: (onResolved, onRejected, _nameSuffix = 'then') ->
      ###
      Implements 'then'-semantics to be compatible with standard JS Promise.
      Both arguments are optional but at least on of them must be defined!
      @param (optional)Function onResolved callback to be evaluated in case of successful resolving of the promise
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
      result._boundTo = @_boundTo
      result.withoutTimeout() if @_noTimeout or not global.config?.debug.future.trackInternalTimeouts
      if typeof onResolved == 'function'
        @_done(thenHandleCb, result, onResolved)
      else
        @_done(@resolve, result)
      if typeof onRejected == 'function'
        @_fail(thenHandleCb, result, onRejected)
      else
        @_fail(@reject, result)
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

      return Future.rejected(new Error("Invalid predicate")) if not _.isFunction(predicate)

      if predicate.prototype instanceof Error
        do (errorClass = predicate) =>
          predicate = (e) -> e instanceof errorClass

      this.catch (err) =>
        if predicate(err)
          callback?.call(@_boundTo, err)
        else
          throw err


    spread: (onResolved, onRejected) ->
      ###
      Like then but expands Array result of the Future to the multiple arguments of the onResolved or onRejected function call.
      ###
      result = Future.single("#{@_name} -> spread")
      result._boundTo = @_boundTo
      result.withoutTimeout() if @_noTimeout or not global.config?.debug.future.trackInternalTimeouts
      if typeof onResolved == 'function'
        @_done(spreadHandleCb, result, onResolved)
      else
        @_done(@resolve, result)
      if typeof onRejected == 'function'
        @_fail(spreadHandleCb, result, onRejected)
      else
        @_fail(@reject, result)
      result


    map: (callback) ->
      ###
      Creates new Future by applying the given callback to the successful result of this Future.
      Resolves resulting future with the result of the callback.
      If callback returns an Array than it's considered as a list of results. If it is necessary to return a single
       array than callback must return an Array with single item containing the resulting Array (Array in Array).
      If this Future is rejected than the resulting Future will contain the same error.
      ###
      console.trace 'DEPRECATION WARNING: Future.map is deprecated, use Future.then instead!'
      result = Future.single("#{@_name} -> map")
      result.withoutTimeout() if @_noTimeout or not global.config?.debug.future.trackInternalTimeouts
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
      console.trace 'DEPRECATION WARNING: Future.flatMap is deprecated, use Future.then instead!'
      result = Future.single("#{@_name} -> flatMap")
      result.withoutTimeout() if @_noTimeout or not global.config?.debug.future.trackInternalTimeouts
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
      console.trace 'DEPRECATION WARNING: Future.andThen alias is deprecated, use Future.finally instead!'
      @finally(callback)


    zip: (those...) ->
      ###
      Zips the values of this and that future, and creates a new future holding the tuple of their results.
      If some of the futures have several results that they are represented as array, not "flattened".
      No result represented as undefined value.
      @deprecated
      @param Future those another futures
      @return Future
      ###
      console.trace 'DEPRECATION WARNING: Future.zip is deprecated, use Future.all instead!'
      those.unshift(this)
      Future.all(those, "#{@_name} -> zip").then (result) -> result


    get: (propertyName) ->
      ###
      This is a convenience method for doing:
        promise.then(function(data) {
            return data[propertyName];
        });
      If propertyName is number and is negative, the indexed load will become data.length + propertyName.
      So that -1 can be used to read last item in the array, -2 to read the second last and so on.
      If the propertyName is still negative after data.length + propertyName, it will be clamped to 0
      @param String|Number property name for object or index for array
      @return Future
      ###
      @then (data) ->
        if data == undefined
          return undefined

        if Array.isArray(data) and typeof propertyName == 'number' and propertyName < 0
          propertyName = Math.max(0, data.length + propertyName)

        data[propertyName]


    isResolved: ->
      ###
      Part of the FutureInspection interface
      Is inspected Future resolved
      @return {Boolean}
      ###
      @_state == 'resolved'


    isPending: ->
      ###
      Part of the FutureInspection interface
      Is inspected Future pending
      @return {Boolean}
      ###
      @_state == 'pending'


    isRejected: ->
      ###
      Part of the FutureInspection interface
      Is inspected Future rejected
      @return {Boolean}
      ###
      @_state == 'rejected'


    value: ->
      ###
      Part of the FutureInspection interface.
      Returns resolve value of Future.
      Throws an error if future is not resolved. You should check method `isResolved` firstly.
      @return {*}
      ###
      if @isResolved()
        @_settledValue
      else
        throw new Error('Inspected future is not resolved')


    reason: ->
      ###
      Part of the FutureInspection interface.
      Returns rejection reason of Future.
      Throws an error if future is not rejected. You should check method `isRejected` firstly.
      @return {Error}
      ###
      if @isRejected()
        @_settledValue
      else
        throw new Error('Inspected future is not rejected')


    @all: (futureList, name = ':all:') ->
      ###
      Converts Array<Thenable<Any>|Any> to Future<Array<Any>>
      If the given array's element is thenable then it's eventual resolved value is put to the result array,
       otherwise the element is passed to the result array as-is.
      @param {Array<Any>} futureList
      @param {String} name - result promise debug name
      @return {Future<Array<Any>>}
      ###
      if not Array.isArray(futureList)
        return Future.rejected(new Error('Bad argument for Future.all()'))
      promise = new Future(name)
      result = []
      for f, i in futureList
        do (i) ->
          if f and typeof f.then == 'function'
            promise.fork()
            f.then(
              (res) ->
                result[i] = res
                promise.resolve()
                return
              (e) ->
                promise.reject(e)
                return
            )
          else
            result[i] = f
          if f instanceof Future and f._noTimeout
            promise.withoutTimeout()
      promise.then ->
        result.__canHaveLengthOne = true  if result.length == 1
        result


    # @deprecated alias
    @sequence: (futureList, name = ':sequence:') ->
      console.trace 'DEPRECATION WARNING: Future.sequence alias is deprecated, use Future.all instead!'
      @all(futureList, name)


    @any: (futureList) ->
      ###
      Returns new future which completes successfully when one of the given futures completes successfully (which comes
       first). Resulting future resolves with that first-completed future's result. All subsequent completing
       futures are ignored.
      Result completes with failure if all of the given futures fails.
      @param {Array<Future<Any>>} futureList
      @return {Future<Any>}
      @todo maybe need to support noTimeout property of futureList promises
      ###
      result = @single(':race:')
      ready = false
      failCounter = futureList.length
      for f in futureList
        f.done (value) ->
          if not ready
            ready = true
            result.resolve(value)
        .fail (err) ->
          failCounter--
          result.reject(err)  if failCounter == 0
      result


    @settle: (futureList) ->
      ###
      Returns a new Future, with always resolved (never rejected) only after each future of futureList
      is resolved or rejected. Returned future resolves to array of FutureInspection instances

      futureList can also be a future, resolves to Array

      @param {Array.<Future|*>|Future.<Array.<Future|*>>} futureList
      @return {Future.<Array.<FutureInspection>>}
      ###
      Future.try(-> futureList).then (futureList) =>
        if not Array.isArray(futureList)
          throw new Error('Bad argument for Future.settle()')

        Future.all(
          for f in futureList
            if not (f instanceof Future)
              f = Future.resolved(f)
            do (inspection = new FutureInspection(f)) -> f.then(-> inspection).catch(-> inspection)
        )


    _runDoneCallbacks: ->
      ###
      Triggers execution of onResolved callbacks waiting for this promise.
      ###
      @_state = 'resolved'
      @_clearUnhandledTracking() if unhandledSoftTracking and not @_locked
      flushCallbackQueue(@_doneCallbacks, @_settledValue)


    _runFailCallbacks: ->
      ###
      Triggers execution of onRejected callbacks waiting for this promise.
      ###
      flushCallbackQueue(@_failCallbacks, @_settledValue)


    # syntax-sugar constructors

    @single: (name = ':single:') ->
      ###
      Returns the future, which can not be forked and must be resolved by only single call of resolve().
      @return Future
      ###
      (new Future(1, name)).lock()


    @resolved: (value) ->
      ###
      Returns the future already resolved with the given arguments.
      @return Future
      ###
      if value != undefined
        @single(':resolved:').resolve(value)
      else
        preallocatedResolvedEmptyPromise


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
      Returns promise with single module if single module is requested and promise with array of modules otherwise.
      @param {String*|Array<String>} paths - list of modules requirejs-format paths
      @return {Future<Any>} or {Future<Array<Any>>}
      ###
      paths = paths[0] if paths.length == 1 and _.isArray(paths[0])
      result = @single(':require:('+ paths.join(', ') + ')')
      require paths, ->
        try
          result.resolve(if arguments.length == 1 then arguments[0] else Array.prototype.slice.call(arguments, 0))
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
      @_clearDebugTimeout()  if unresolvedTrackingEnabled
      @_noTimeout = true
      this


    _initDebugTimeout: ->
      @_trackId or= _.uniqueId()
      unresolvedMap[@_trackId] =
        startTime: (new Date).getTime()
        promise: this


    _clearDebugTimeout: ->
      delete unresolvedMap[@_trackId]


    _clearDoneCallbacks: ->
      # Separate method for this simple operation is need to support async-aware profiler (to overwrite this method)
      @_doneCallbacks = null


    _clearFailCallbacks: ->
      # Separate method for this simple operation is need to support async-aware profiler (to overwrite this method)
      @_failCallbacks = null


    clear: ->
      ###
      Way to eliminate any impact of resolving or rejecting or time-outing of this promise.
      Should be used when actions that are waiting for this promise completion are no more needed.
      ###
      # preallocated empty promise is shared and should never be cleaned, as it can break logic in another place
      return if this == preallocatedResolvedEmptyPromise
      @_clearDoneCallbacks()
      @_clearFailCallbacks()
      @_clearDebugTimeout() if unresolvedTrackingEnabled
      @_clearUnhandledTracking() if unhandledTrackingEnabled
      @_state = 'cleaned'
      return


    toJSON: ->
      ###
      Serialization of promises is not supported.
      ###
      null


    toJSON: ->
      ###
      Serialization of promises is not supported.
      ###
      null


    # debugging

    _initUnhandledTracking: ->
      ###
      Registers the promise to the unhandled failure tracking map.
      ###
      @_trackId or= _.uniqueId()
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


  ##
  # TRY-CATCH OPTIMIZATION TRICK (stolen from bluebird)
  ##

  # Try catch is not supported in optimizing
  # compiler, so it is isolated
  errorObj = e: {}
  tryCatchTarget = undefined
  tryCatcher = ->
    try
      tryCatchTarget.apply(this, arguments)
    catch e
      errorObj.e = e
      errorObj

  tryCatch = (fn) ->
    tryCatchTarget = fn
    tryCatcher


  ##
  # Shared routine callback functions that allow to avoid redundant closures creation for each call
  ##

  asapDoneCb = ->
    # see Future._done
    @_clearFailCallbacks()
    @_runDoneCallbacks()


  asapFailCb = ->
    # see Future._fail
    @_runFailCallbacks()


  failAloudCb = (err, message) ->
    # see Future.failAloud
    reportArgs = ["Future(#{@_name})::failAloud#{ if message then " with message: #{message}" else '' }"]
    if err
      reportArgs.push("\n#{err}")
      reportArgs.push("\n" + filterStack(err.stack))
    if @_stack
      reportArgs.push("\n---------------")
      recCollectLongStackTrace(this, reportArgs)
    cons().error.apply(cons(), reportArgs)


  thenHandleCb = (value, fn) ->
    # see Future.then
    prevContextPromise = currentContextPromise
    currentContextPromise = this
    res = tryCatch(fn).call(@_boundTo, value)
    currentContextPromise = prevContextPromise
    if res == errorObj
      if @completed()
        throw res.e
      else
        @reject(res.e)
    else if res instanceof Future
      @when(res)
    else if _.isArray(res)
      if res.length == 1 and _.isArray(res[0]) and not res.__canHaveLengthOne
        cons().warn "DEPRECATION WARNING: returning of array in array as promise callback result hack detected for promise with name '#{@_name}'. This behaviour is deprecated, return just array without any wrapper!", this._stack
        res = res[0]
      @resolve(res)
    else
      @resolve(res)
    return


  spreadHandleCb = (value, fn) ->
    # see Future.spread
    prevContextPromise = currentContextPromise
    currentContextPromise = this
    res = tryCatch(fn).apply(@_boundTo, value)
    currentContextPromise = prevContextPromise
    if res == errorObj
      if @completed()
        throw res.e
      else
        @reject(res.e)
    else if res instanceof Future
      @when(res)
    else if _.isArray(res)
      if res.length == 1 and _.isArray(res[0]) and not res.__canHaveLengthOne
        cons().warn "DEPRECATION WARNING: returning of array in array as promise callback result hack detected for promise with name '#{@_name}'. This behaviour is deprecated, return just array without any wrapper!", this._stack
        res = res[0]
      @resolve(res)
    else
      @resolve(res)
    return


  finallyDoneCb = (value, fn) ->
    # see Future.finally
    prevContextPromise = currentContextPromise
    currentContextPromise = this
    res = tryCatch(fn).call(@_boundTo, null, value)
    currentContextPromise = prevContextPromise
    if res == errorObj
      if @completed()
        throw res.e
      else
        @reject(res.e)
    else
      @resolve(value)
    return


  finallyFailCb = (reason, fn) ->
    # see Future.finally
    prevContextPromise = currentContextPromise
    currentContextPromise = this
    res = tryCatch(fn).call(@_boundTo, reason)
    currentContextPromise = prevContextPromise
    if res == errorObj
      if @completed()
        throw res.e
      else
        @reject(res.e)
    else
      # doesn't need to take responsibility for the parent promise's error
      @_clearUnhandledTracking()  if unhandledTrackingEnabled
      @reject(reason)
    return


  bindResolvedCb = (resolvedThisArg, result) ->
    # see Future.bind
    result._boundTo = resolvedThisArg
    result.when(this)


  ##
  # TASK QUEUE HANDLING ROUTINES
  ##

  addCallbackToQueue = (queue, fn, ctx, passArg) ->
    ###
    DRY method adding task to the given task queue
    ###
    queue[queue.length] = fn
    queue[queue.length] = ctx
    queue[queue.length] = passArg
    return


  capacity = 1024

  flushCallbackQueue = (queue, settledValue) ->
    ###
    Executes all tasks from the given queue.
    Task - three consequent elements of the array interpreted as:
     * first - the callback function
     * second - the context object for which function should be called (can be empty)
     * third - any additional argument passed to the callback function as a second argument after the given settledValue
    During execution new tasks may be appended to the queue by the previous tasks, they are also executed.
    At the end the task queue is cleaned.
    The technique is copied from the asap library.
    @param {Array} queue
    @param {Any} settledValue - the resulting value of the promise (success or failure)
    ###
    return if not queue
    index = 0
    while index < queue.length
      currentIndex = index
      # Advance the index before calling the task. This ensures that we will
      # begin flushing on the next task the task throws an error.
      index += 3;
      queue[currentIndex].call(queue[currentIndex + 1], settledValue, queue[currentIndex + 2])
      # Prevent leaking memory for long chains of recursive calls to `asap`.
      # If we call `asap` within tasks scheduled by `asap`, the queue will
      # grow, but to avoid an O(n) walk for every task we execute, we don't
      # shift tasks off the queue after they have been executed.
      # Instead, we periodically shift 1024 tasks off the queue.
      if index > capacity
        # Manually shift all values starting at the index back to the
        # beginning of the queue.
        scan = 0
        len = queue.length - index
        while scan < len
          queue[scan] = queue[scan + index]
          scan++
        queue.length -= index
        index = 0
    queue.length = 0
    return


  ##
  # DEBUGGING SUPPORT FUNCTIONS
  ##

  splitAndRawFilterStack = (stackStr) ->
    ###
    @param {String} stackArr
    @return {Array<String>}
    ###
    return [] if not _.isString(stackStr)
    stackStr
      .split("\n")
      .slice(1)
      .filter (x) ->
        x.indexOf('Future.js') == -1 and
        x.indexOf('require.js') == -1 and
        x.indexOf('/r.js') == -1 and
        x.indexOf('raw.js') == -1


  filterStack = (stackStr, promiseName, parentStackStr) ->
    ###
    Beautifies and returns given stack-trace string.
    Filters Future.js and require.js lines. Also filters lines intersecting with the parent promise stack trace.
    @param {String} stackStr
    @param {String} promiseName
    @param {String} parentStackStr
    @return {String}
    ###
    stackArr = splitAndRawFilterStack(stackStr)
    if parentStackStr
      parentStackArr = splitAndRawFilterStack(parentStackStr)
      stackArr = _.difference(stackArr, parentStackArr)
    stackArr
      .map (x) -> x + (if longStackTraceAppendName and promiseName then " [#{promiseName}]" else '')
      .join("\n")


  recCollectLongStackTrace = (promise, args) ->
    ###
    Recursively collects beautified long stack-trace for the hierarchy of promises into the given args array.
    @param {Future} promise
    @param {Array} args
    ###
    if promise._stack
      args.push("\n" + filterStack(promise._stack, promise._name, promise._parent?._stack))
    if promise._parent
      recCollectLongStackTrace(promise._parent, args)
    return


  initTimeoutTracker = ->
    ###
    Initializes infinite checking of promises with unhandled failure result.
    ###
    unhandledSoftTracking = !!global.config?.debug.future.trackUnhandled.soft
    interval = parseInt(global.config?.debug.future.trackUnhandled.interval)
    unhandledTimeout = parseInt(global.config?.debug.future.trackUnhandled.timeout)
    unresolvedTimeout = parseInt(global.config?.debug.future.timeout)
    unhandledMap = {}
    unresolvedMap = {}
    if interval > 0
      setInterval ->
        curTime = (new Date).getTime()

        for id, info of unresolvedMap
          elapsed = curTime - info.startTime
          if elapsed > unresolvedTimeout
            pr = info.promise
            if pr.state() == 'pending' and pr._counter > 0
              reportArgs = ["Future timed out [#{pr._name}] (#{elapsed / 1000} seconds), counter = #{pr._counter}"]
              reportArgs.push("\n" + filterStack(pr._stack))  if pr._stack
              recCollectLongStackTrace(info.promise, reportArgs)
              if longStackTraceLogOriginStack and info.promise._stack
                  reportArgs.push("\n-------- Origin stack --------")
                  reportArgs.push(info.promise._stack.split("\n").slice(1).join("\n"))
                  reportArgs.push("\n------------------------------")
              cons().warn.apply(cons(), reportArgs)
            delete unresolvedMap[id]

        for id, info of unhandledMap
          elapsed = curTime - info.startTime
          if elapsed > unhandledTimeout
            state = info.promise.state()
            if state != 'pending'
              reportArgs = [
                "Unhandled rejection detected for [#{state}] Future[#{info.promise._name}] " +
                  "after #{elapsed / 1000} seconds!"
              ]
              if state == 'rejected'
                err = info.promise._settledValue
                reportArgs.push("\n#{err}")
                reportArgs.push("\n" + filterStack(err.stack))  if err.stack
                recCollectLongStackTrace(info.promise, reportArgs)
                if longStackTraceLogOriginStack
                  reportText = if info.promise._stack then info.promise._stack.split("\n").slice(1).join("\n") else ''
                  reportArgs.push("\n-------- Origin stack --------")
                  reportArgs.push(reportText)
                  reportArgs.push("\n------------------------------")
              cons().warn.apply(cons(), reportArgs)
            delete unhandledMap[id]
      , interval


  longStackTraceEnabled = !!global.config?.debug.future.longStackTrace.enable
  longStackTraceAppendName = !!global.config?.debug.future.longStackTrace.appendPromiseName
  longStackTraceLogOriginStack = longStackTraceEnabled and !!global.config?.debug.future.longStackTrace.logOriginStack
  unhandledTrackingEnabled = !!global.config?.debug.future.trackUnhandled.enable
  unresolvedTrackingEnabled = !!global.config?.debug.future.timeout
  initTimeoutTracker()  if unhandledTrackingEnabled or unresolvedTrackingEnabled
  preallocatedResolvedEmptyPromise = Future.single(':empty:').resolve()

  Future

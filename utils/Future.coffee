define [
  'underscore'
], (_) ->

  throwExceptionCallback = (err) -> throw err

  class Future
    ###
    Simple aggregative future/promise class.

    Two scenarios are supported:
    1. Do something when all async actions in loop are complete.
    2. Aggregate several typical async-callback functions result into one callback call.

    Example of 1:
      promise = new Future
      result = []
      for i in [1..10]
        promise.fork()
        setTimeout ->
          result.push(i)
          promise.resolve()
        , 1000
      promise.done ->
        _console.log result.join(', ')

    Example of 2:
      asyncGetter = (key, callback) ->
        obj =
          test: [1, 2, 3, 4, 5]
        setTimeout ->
          callback(obj[key])
        , 500

      promise = new Future
      require ['jquery', 'underscore'], promise.callback()
      asyncGetter 'test', promise.callback()
      promise.done ($, _, testVal) ->
        $('body').html("Even vals of 'test' = #{ _.filter(testVal, (num) -> num % 2 == 0) }")
    ###

    _counter: 0
    _doneCallbacks: null
    _failCallbacks: null
    _order: 0
    _callbackArgs: null

    _locked: false
    # completed by any way
    _completed: false
    # current state: pending, resolved or rejected
    _state: 'pending'

    # helpful to identify the future during debugging
    _name: ''


    constructor: (initialCounter = 0, name = '') ->
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


    fork: ->
      ###
      Adds one more value to wait.
      Should be paired with following resolve() call.
      @return Future(self)
      ###
      throw Error("Trying to use the completed promise!") if @_completed
      throw Error("Trying to fork locked promise!") if @_locked
      @_counter++
      this


    resolve: (args...) ->
      ###
      Indicates that one of the waiting values is ready.
      If there are some arguments passed then they are passed unchanged to the done-callbacks.
      If there is no value remaining in the aggregate and done method is already called
       than callback is fired immedialtely.
      Should have according fork() call before.
      ###
      if @_counter > 0
        @_counter--
        if @_state != 'rejected'
          @_callbackArgs = [args] if args.length > 0
          @_runDoneCallbacks() if @_counter == 0 and @_doneCallbacks.length > 0
          # not changing state to 'resolved' here because it is possible to call fork() again if done hasn't called yet
      else
        nameStr = if @_name then " (name = #{ @_name})" else ''
        throw new Error("Future::resolve() is called more times than Future::fork!#{ nameStr }")

      this


    reject: (args...) ->
      ###
      Indicates that the promise is rejected (failed) and fail-callbacks should be called.
      If there are some arguments passed then they are passed unchanged to the done-callbacks.
      If fail-method is already called than callbacks are fired immediately, otherwise they'll be fired
       when fail-method is called.
      Only first call of this method is important. Any subsequent calls does nothing but decrementing the counter.
      ###
      if @_counter > 0
        @_counter--
        if @_state != 'rejected'
          @_state = 'rejected'
          @_callbackArgs = [args] if args.length > 0
          @_runFailCallbacks() if @_failCallbacks.length > 0
      else
        throw new Error("Future::reject is called more times than Future::fork!")

      this


    when: (args...) ->
      ###
      Adds another future(promise)(s) as a condition of completion of this future
      Can be called multiple times.
      @param (variable)Future args another future which'll be waited
      @return Future self
      ###
      for promise in args
        @fork() if not @_locked
        promise
          .done((args...) => @resolve.apply(this, args))
          .fail((args...) => @reject.apply(this, args))
      this


    done: (callback) ->
      ###
      Defines callback function to be called when future is resolved.
      If all waiting values are already resolved then callback is fired immedialtely.
      If done method is called several times than all passed functions will be called.
      ###
      @_doneCallbacks.push(callback)
      @_runDoneCallbacks() if @_counter == 0 and @_state != 'rejected'
      this


    fail: (callback) ->
      ###
      Defines callback function to be called when future is rejected.
      If all waiting values are already resolved then callback is fired immedialtely.
      If done method is called several times than all passed functions will be called.
      ###
      throw new Error("Invalid argument for Future.fail(): #{ callback }") if not _.isFunction(callback)
      @_failCallbacks.push(callback)
      @_runFailCallbacks() if @_state == 'rejected'
      this


    failAloud: ->
      ###
      Adds often-used scenario of fail that just throws exception with the error
      ###
      @fail(throwExceptionCallback)


    callback: (neededArgs...) ->
      ###
      Generates callback proxy function to be used in return-in-async-callback functions
       which allows to avoid callback-indentation hell by merging callback callback calls
       of severar such functions into one callback which is called when all async functions
       are complete.

      All arguments of aggregated callbacks are passed to 'done'-defined callback in order of calling
       'callback' method.

      @see example 2 in class documentation block
      ###
      @fork()
      order = @_order++
      @_callbackArgs ?= {}
      (args...) =>
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


    state: ->
      ###
      Returns state of the promise - 'pending', 'resolved' or 'rejected'
      @return String
      ###
      @_state


    lock: ->
      @_locked = true
      this


    zip: (those...) ->
      ###
      Zips the values of this and that future, and creates a new future holding the tuple of their results.
      @param Future those another futures
      @return Future
      ###
      result = new Future
      those.push(this)
      result.when.apply(result, those)


    _runDoneCallbacks: ->
      ###
      Fires resulting callback functions defined by done with right list of arguments.
      ###
      @_state = 'resolved'
      # this is need to avoid duplicate callback calling in case of recursive coming here from callback function
      callbacksCopy = @_doneCallbacks
      @_doneCallbacks = []
      @_runCallbacks(callbacksCopy)


    _runFailCallbacks: ->
      ###
      Fires resulting callback functions defined by fail with right list of arguments.
      ###
      # this is need to avoid duplicate callback calling in case of recursive coming here from callback function
      callbacksCopy = @_failCallbacks
      @_failCallbacks = []
      @_runCallbacks(callbacksCopy)


    _runCallbacks: (callbacks) ->
      ###
      Helper-method to run list of callbacks.
      @param Array(Function) callbacks
      ###
      @_completed = true

      if @_callbackArgs?
        args = []
        for i in [0..@_order-1]
          args = args.concat(@_callbackArgs[i])
        callback.apply(null, args) for callback in callbacks
      else
        callback() for callback in callbacks


    # syntax-sugar constructors

    @single: (name = '')->
      ###
      Returns the future, which can not be forked and must be resolved by only single call of resolve().
      @return Future
      ###
      (new Future(1, name)).lock()


    @resolved: (args...) ->
      ###
      Returns the future already resolved with the given arguments.
      @return Future
      ###
      result = @single()
      result.resolve.apply(result, args)
      result


    @rejected: (error) ->
      ###
      Returns the future already rejected with the given error
      @param Any error
      @return Future
      ###
      result = @single()
      result.reject(error)
      result

    @timeout: (millisec) ->
      ###
      Returns the future wich will complete after the given number of milliseconds
      @param Int millisec number of millis before resolving the future
      @return Future
      ###
      result = @single()
      setTimeout ->
        result.resolve()
      , millisec
      result


    # debugging

    _debug: (args...) ->
      ###
      Debug logging method, which logs future's name, counter, callback lenght, and given arguments.
      Can emphasise futures with desired names by using console.warn.
      ###
      if @_name.indexOf('desired search in name') != -1
        fn = _console.warn
      else
        fn = _console.log
      args.unshift(@_name)
      args.unshift(@_doneCallbacks.length)
      args.unshift(@_counter)
      fn.apply(_console, args)

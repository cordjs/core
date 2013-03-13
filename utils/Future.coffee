define [], () ->

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
        console.log result.join(', ')

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
    _callbacks: null
    _order: 0
    _callbackArgs: null

    constructor: (initialCounter = 0) ->
      @_counter = initialCounter
      @_callbacks = []


    fork: ->
      ###
      Adds one more value to wait.
      Should be paired with following resolve() call.
      @return Future(self)
      ###
      @_counter++
      this


    resolve: (args...) ->
      ###
      Indicates that one of the waiting values is ready.
      If there are some arguments passed then they are passed unchanged to the done-callback.
      If there is no value remaining in the aggregate and done method is already called
       than callback is fired immedialtely.
      Should have according fork() call before.
      ###
      if @_counter > 0
        @_callbackArgs = [args] if args.length > 0
        @_counter--
        @_runCallbacks() if @_counter == 0 and @_callbacks.length > 0
      else
        throw new Error("Future::resolve is called more times than Future::fork!")


    done: (callback) ->
      ###
      Defines callback function to be called when future is completed.
      If all waiting values are already resolved then callback is fired immedialtely.
      If done method is called several times than all passed functions will be called.
      ###
      @_callbacks.push(callback)
      @_runCallbacks() if @_counter == 0


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


    _runCallbacks: ->
      ###
      Fires resulting callback functions defined by done with right list of arguments.
      ###
      if @_callbackArgs?
        args = []
        for i in [0..@_order-1]
          args = args.concat(@_callbackArgs[i])
        callback.apply(null, args) for callback in @_callbacks

        @_order = 0
        @_callbackArgs = null
      else
        callback() for callback in @_callbacks

      @_callbacks = []

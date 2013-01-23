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
    _callback: null
    _order: 0
    _callbackArgs: null


    fork: ->
      ###
      Adds one more value to wait.
      Should be paired with following resolve() call.
      @return Future(self)
      ###
      @_counter++
      this


    resolve: ->
      ###
      Indicates that one of the waiting values is ready.
      In there is no value remaining in the aggregate and done method is already callled
       than callback is fired immedialtely.
      Should have according fork() call before.
      ###

      if @_counter > 0
        @_counter--
        @_runCallback() if @_counter == 0 and @_callback?
      else
        throw new Error("Future::resolve is called more times than Future::fork!")


    done: (callback) ->
      ###
      Defines callback function to be called when future is completed.
      If all waiting values are already resolved then callback is fired immedialtely.
      ###
      @_callback = callback
      @_runCallback() if @_counter == 0


    callback: ->
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
        @_callbackArgs[order] = args
        @resolve()


    _runCallback: ->
      ###
      Fires resulting callback defined in done with right list of arguments.
      ###

      if @_callbackArgs?
        args = []
        for i in [0..@_order-1]
          args = args.concat(@_callbackArgs[i])
        @_callback.apply(null, args)

        @_order = 0
        @_callbackArgs = null
      else
        @_callback()

      @_callback = null

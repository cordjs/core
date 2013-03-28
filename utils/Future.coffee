define [
  'underscore'
], (_) ->

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
    _completed: false

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
      @_callbacks = []
      @_name = name


    fork: ->
      ###
      Adds one more value to wait.
      Should be paired with following resolve() call.
      @return Future(self)
      ###
      throw Error("Trying to use the completed promise!") if @_completed
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


    when: (args...) ->
      ###
      Adds another future(promise)(s) as a condition of completion of this future
      Can be called multiple times.
      @param (variable)Future args another future which'll be waited
      @return Future self
      ###
      for promise in args
        @fork()
        promise.done => @resolve()
      this


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


    completed: ->
      @_completed


    _runCallbacks: ->
      ###
      Fires resulting callback functions defined by done with right list of arguments.
      ###
      @_completed = true

      # this is need to avoid duplicate callback calling in case of recursive coming here from callback function
      callbacksCopy = @_callbacks
      @_callbacks = []

      if @_callbackArgs?
        args = []
        for i in [0..@_order-1]
          args = args.concat(@_callbackArgs[i])
        callback.apply(null, args) for callback in callbacksCopy
      else
        callback() for callback in callbacksCopy


    _debug: (args...) ->
      ###
      Debug logging method, which logs future's name, counter, callback lenght, and given arguments.
      Can emphasise futures with desired names by using console.warn.
      ###
      if @_name.indexOf('desired search in name') != -1
        fn = console.warn
      else
        fn = console.log
      args.unshift(@_name)
      args.unshift(@_callbacks.length)
      args.unshift(@_counter)
      fn.apply(console, args)

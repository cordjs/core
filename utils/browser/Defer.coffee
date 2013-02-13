define ->

  class Defer
    @timeouts: []
    @messageName: 'zero-timeout-message'

    @counter: 0

    @nextTick: (fn) ->
      ###
      Like setTimeout, but only takes a function argument.  There's
      no time argument (always zero) and no arguments (you have to
      use a closure).
      ###
      @timeouts.push(fn)
      @counter++
      window.postMessage(@messageName, "*")


    @handleMessage: (event) ->
      if event.source == window && event.data == Defer.messageName
        event.stopPropagation()
        if Defer.timeouts.length > 0
          fn = Defer.timeouts.shift()
          fn()
          Defer.counter--



  window.addEventListener('message', Defer.handleMessage, true)

  Defer

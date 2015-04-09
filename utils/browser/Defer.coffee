define ->

  messageName = 'zero-timeout-message'
  tasks = []


  handleMessage = (event) ->
    if event.source == window and event.data == messageName
      event.stopPropagation()
      if tasks.length > 0
        fn = tasks.shift()
        fn()

  window.addEventListener('message', handleMessage, true)


  nextTick: (fn) ->
    ###
    Like setTimeout, but only takes a function argument.  There's no time argument (always zero) and no arguments
     (you have to use a closure).
    ###
    tasks.push(fn)
    window.postMessage(messageName, "*")

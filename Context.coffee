define [
  'postal'
  'underscore'
], (postal, _) ->

  class Context

    constructor: (arg1, arg2) ->
      if typeof arg1 is 'object'
        for key, value of arg1
          @[key] = value
      else
        @id = arg1
        if arg2
          for key, value of arg2
            @[key] = if _.isFunction value then value() else value


    set: (args...) ->
      triggerChange = false
      if args.length == 0
        throw "Invalid number of arguments! Should be 1 or 2."
      else if args.length == 1
        pairs = args[0]
        if typeof pairs is 'object'
          for key, value of pairs
            if @setSingle key, value
              triggerChange = true
        else
          throw "Invalid argument! Single argument must be key-value pair (object)."
      else if @setSingle args[0], args[1]
        triggerChange = true

      if triggerChange
        setTimeout =>
          postal.publish "widget.#{ @id }.someChange", {}
        , 0


    setSingle: (name, newValue) ->
      triggerChange = false

      if newValue?
        if @[name]?
          oldValue = @[name]
          if oldValue != newValue
            triggerChange = true
        else
          triggerChange = true

#      console.log "setSingle -> #{ name } = #{ newValue } (oldValue = #{ @[name] }) trigger = #{ triggerChange }"

      @[name] = newValue if typeof newValue != 'undefined'

      if triggerChange
        setTimeout =>
          console.log "publish widget.#{ @id }.change.#{ name }" if global.CONFIG.debug?.widget
          postal.publish "widget.#{ @id }.change.#{ name }",
            name: name
            value: newValue
            oldValue: oldValue
        , 0

      triggerChange


    setDeferred: (args...) ->
      (@[name] = ':deferred') for name in args

    isDeferred: (name) ->
      @[name] is ':deferred'

    isEmpty: (name) ->
      (not @[name]?) or @isDeferred(name)

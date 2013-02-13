define [
  'cord!Collection'
  'cord!Model'
  'cord!utils/Defer'
  'cord!utils/Future'
  'postal'
  'underscore'
], (Collection, Model, Defer, Future, postal, _) ->

  class Context

    constructor: (arg1, arg2) ->
      if typeof arg1 is 'object'
        for key, value of arg1
          @[key] = value
      else
        @id = arg1
        if arg2
          for key, value of arg2
            @[key] = value


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
        Defer.nextTick =>
          postal.publish "widget.#{ @id }.someChange", {}


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
        Defer.nextTick =>
          console.log "publish widget.#{ @id }.change.#{ name }" if global.CONFIG.debug?.widget
          postal.publish "widget.#{ @id }.change.#{ name }",
            name: name
            value: newValue
            oldValue: oldValue

      triggerChange


    setDeferred: (args...) ->
      (@[name] = ':deferred') for name in args

    isDeferred: (name) ->
      @[name] is ':deferred'

    isEmpty: (name) ->
      (not @[name]?) or @isDeferred(name)


    toJSON: ->
      result = {}
      for key, value of this
        if value instanceof Collection
          result[key] = value.serializeLink()
        else if value instanceof Model
          result[key] = value.serializeLink()
        else
          result[key] = value
      result


    @fromJSON: (obj, ioc, callback) ->
      promise = new Future
      for key, value of obj
        do (key, value) ->
          if Collection.isSerializedLink(value)
            promise.fork()
            Collection.unserializeLink value, ioc, (collection) ->
              obj[key] = collection
              promise.resolve()
          else if Model.isSerializedLink(value)
            promise.fork()
            Model.unserializeLink value, ioc, (model) ->
              obj[key] = model
              promise.resolve()
          else
            obj[key] = value

      promise.done =>
        callback(new this(obj))

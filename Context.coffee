define [
  'cord!Collection'
  'cord!Model'
  'cord!utils/Future'
  'asap/raw'
  'postal'
  'underscore'
  'cord!Console'
  'cord!isBrowser'
  'cord!dustPlugins'
], (Collection, Model, Future, asap, postal, _, _console, isBrowser, dustPlugins) ->

  # support for deferred timeout tracking
  deferredTrackingEnabled = false
  deferredTrackMap = null


  class Context

    constructor: (arg1, arg2) ->
      ###
      @param {Object|String} arg1 initial context values or widget ID
      @param (optional) {Object} arg2 initial context values (if first value is ID
      ###
      @[':internal'] =
        version: 0
        promises: {}

      initCtx = {}

      if _.isObject(arg1)
        initCtx = arg1
      else
        @id = arg1
        initCtx = arg2 if _.isObject(arg2)

      for key, value of initCtx
        @[key] = value
        @_initDeferredDebug(key)  if value == ':deferred' and deferredTrackingEnabled


    setOwnerWidget: (owner) ->
      if owner
        Object.defineProperty this, '_ownerWidget',
          value: owner
          writable: true
          enumerable: false
      @_ownerWidget


    set: (args...) ->
      ###
      Changes single or multiple context values.
      Accepts object argument with key-value pairs or two arguments - String name and value
      ###
      if args.length == 0
        throw new Error('Invalid number of arguments! Should be 1 or 2.')
      else if args.length == 1
        pairs = args[0]
        if typeof pairs == 'object'
          changed = false
          for key, value of pairs
            changed = true  if @_setSingle(key, value)
          changed
        else
          throw new Error("Invalid argument! Single argument must be key-value pair (object).")
      else
        @_setSingle args[0], args[1]


    setSingle: (name, newValue, callbackPromise) ->
      ###
      @deprecated Use Context::set() instead
      ###
      console.trace 'DEPRECATED WARNING: ctx.setSingle is deprecated, use ctx.set instead!'
      @_setSingle(name, newValue, callbackPromise)


    _setSingle: (name, newValue, callbackPromise) ->
      ###
      Sets single context param's value.
      If value type is Future then automatically sets to deferred and then to the resolved value
       when the promise completes.
      @param String name param name
      @param Any newValue param value
      @param (optional)Future callbackPromise promise to support setWithCallback() method functionality
      @return Boolean true if the change event was triggered (the value was changed)
      ###
      if dustPlugins[name] != undefined
        throw new Error("You can not use \"#{name}\" as context parameter name")

      if newValue instanceof Future and name.substr(-7) != 'Promise' # workaround pageTitlePromise problem
        @_ownerWidget?.addPromise(newValue)
        triggerChange = @_setSingle(name, ':deferred')
        newValue.then (resolvedValue) =>
          resolvedValue = null if resolvedValue == undefined
          @_setSingle name, resolvedValue
        .catch (err) =>
          # We should keep rejected promise for possible future `getPromise(name)` call
          # (parameter keeps deferred in this case)
          @[':internal'].promises[name] ?= @_newParamPromise(name)
          @[':internal'].promises[name].reject(err)
          # This parameter never will never become resolved, as it rejected
          @_clearDeferredDebug(name) if deferredTrackingEnabled
          return
        return triggerChange

      stashChange = true
      if newValue != undefined
        if @[name] == ':deferred'
          # if the current value special :deferred than event should be triggered even if the new value is null
          triggerChange = (newValue != ':deferred')
          @_clearDeferredDebug(name)  if triggerChange and deferredTrackingEnabled
          # stashing should be turned off for modifying from :deferred except the value has become :deferred during
          #  widget template rendering (when stashing is enabled)
          stashChange = @[':internal'].deferredStash?[name]

        else
          oldValue = @[name]
          if oldValue == null
            # null needs special check because null == null in javascript isn't true
            triggerChange = (newValue != null)
          else
            triggerChange = (newValue != oldValue)

          @_initDeferredDebug(name)  if newValue == ':deferred' and deferredTrackingEnabled
      else
        triggerChange = false

      # never change value to 'undefined' (don't mix up with 'null' value)
      @[name] = newValue if newValue != undefined

      if triggerChange
        callbackPromise.fork() if callbackPromise
        curVersion = ++@[':internal'].version
        if @[':internal'].stash
          if newValue == ':deferred'
            # if the value become deferred during enabled stashing then we should remember it to allow stashing
            #  when it'll set again. Otherwise behaviour can miss some change events emitted during widget rendering.
            @[':internal'].deferredStash ?= {}
            @[':internal'].deferredStash[name] = true
          else if stashChange
            cursor = _.uniqueId()
            @[':internal'].stash.push
              id: @id
              name: name
              newValue: newValue
              oldValue: oldValue
              cursor: cursor
              version: curVersion

        if ':deferred' != newValue and @[':internal'].promises[name]
          @[':internal'].promises[name].resolve(newValue)
          delete @[':internal'].promises[name]

        asap =>
          _console.log "publish widget.#{ @id }.change.#{ name }" if global.config.debug.widget
          postal.publish "widget.#{ @id }.change.#{ name }",
            name: name
            value: newValue
            oldValue: oldValue
            callbackPromise: callbackPromise
            cursor: cursor
            version: curVersion
          callbackPromise.resolve() if callbackPromise

      triggerChange


    setDeferred: (args...) ->
      for name in args
        @_setSingle(name, ':deferred')


    setServerDeferred: (args...) ->
      if not isBrowser
        for name in args
          @_setSingle(name, ':deferred')


    isDeferred: (name) ->
      @[name] is ':deferred'


    getPromise: (name) ->
      ###
      Returns Future of parameter's value.
      ###
      if @isDeferred(name)
        @[':internal'].promises[name] ?= @_newParamPromise(name)
        @[':internal'].promises[name]
      else
        Future.resolved(@[name])


    isEmpty: (name) ->
      (not @[name]?) or @isDeferred(name)


    setWithFeedback: (name, value) ->
      ###
      Sets the context param's value as usual but injects future to the event data and returns it.
      By default if event handlers doesn't support injected callback promise, the future will be completed immediately
       after calling all event handlers. But some event handlers can support the promise and defer their completion
       depending of some of their async activity.
      @param String name param name
      @param Any value param value
      @return Future
      ###
      callbackPromise = new Future('Context::setWithFeedback')
      @_setSingle(name, value, callbackPromise)
      callbackPromise


    stashEvents: ->
      @[':internal'].stash = []


    replayStashedEvents: ->
      ###
      Re-triggers stashed context-change events.
      Stashing is needed after Widget::setParams() is already processed but browserInit() still didn't executed,
       so child widget's and behaviour will miss context changing which ocasionally happens during that time.
      @browser-only
      ###
      if @[':internal'].stash and @[':internal'].stash.length
        originalStash = @[':internal'].stash
        @[':internal'].stash = null
        @[':internal'].deferredStash = null
        asap =>
          for ev in originalStash
            postal.publish "widget.#{ ev.id }.change.#{ ev.name }",
              name: ev.name
              value: ev.newValue
              oldValue: ev.oldValue
              cursor: ev.cursor
              version: ev.version
              stashed: true


    getVersion: ->
      @[':internal'].version


    toJSON: ->
      result = {}
      for own key, value of this
        if value instanceof Collection
          result[key] = value.serializeLink()
        else if value instanceof Model
          result[key] = value.serializeLink()
        else if _.isArray(value) and value[0] instanceof Model
          result[key] = (m.serializeLink() for m in value)
        else if value instanceof Future
          result[key] = null
        else if key == 'i18nHelper' and value.i18nContext? #Save translator context for browser-side
          result[key] = value.i18nContext
        else if key != ':internal'
          result[key] = value
      result


    @fromJSON: (obj, ioc) ->
      promise = new Future('Context::fromJSON')
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
          else if _.isArray(value) and Model.isSerializedLink(value[0])
            obj[key] = []
            for link in value
              promise.fork()
              Model.unserializeLink link, ioc, (model) ->
                obj[key].push(model)
                promise.resolve()
          else
            obj[key] = value

      promise.then => new this(obj)


    clearDeferredTimeouts: ->
      ###
      Prevents debug timeouts for deferred values to be redundantly logged when the owner widget is going to die
      ###
      delete deferredTrackMap[@id] if deferredTrackingEnabled


    _initDeferredDebug: (name) ->
      deferredTrackMap[@id] or= {}
      deferredTrackMap[@id][name] =
        startTime: (new Date).getTime()
        ctx: this


    _clearDeferredDebug: (name) ->
      if deferredTrackMap[@id]
        delete deferredTrackMap[@id][name]
        delete deferredTrackMap[@id]  if _.isEmpty(deferredTrackMap[@id])


    _newParamPromise: (name) ->
      Future.single(@_ownerWidget.debug("<<<ctx.#{name}>>>"))



  initTimeoutTracker = (interval) ->
    ###
    Initializes infinite checking of deferred values that are not resolved until configured timeout.
    ###
    deferredTimeout = parseInt(global.config?.debug.deferred.timeout)
    deferredTrackMap = {}
    if interval > 0
      setInterval ->
        curTime = (new Date).getTime()

        for id, names of deferredTrackMap
          for name, info of names
            elapsed = curTime - info.startTime
            if elapsed > deferredTimeout
              if info.ctx[name] == ':deferred' and not info.ctx._ownerWidget?.isSentenced()
                _console.warn "### Deferred timeout (#{elapsed / 1000} s) " +
                              "for #{info.ctx._ownerWidget?.constructor.__name}(#{id}) <<< ctx.#{name} >>>"
              delete deferredTrackMap[id][name]
              delete deferredTrackMap[id]  if _.isEmpty(deferredTrackMap[id])

      , interval


  interval = parseInt(global.config?.debug.deferred.checkInterval)
  deferredTrackingEnabled = !!global.config?.debug.deferred.timeout and interval > 0
  initTimeoutTracker(interval)  if deferredTrackingEnabled


  Context

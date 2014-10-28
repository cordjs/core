define [
  'cord!Api'
  if CORD_IS_BROWSER then 'cord!Behaviour' else undefined
  'cord!ServiceContainer'
  'cord!templateLoader'
  'cord!Widget'
  'cord!WidgetRepo'
  if CORD_IS_BROWSER then 'cord!init/browserInit' else undefined
  'cord!request/' + if CORD_IS_BROWSER then 'BrowserRequest' else 'ServerRequest'
  'cord!router/' + if CORD_IS_BROWSER then 'clientSideRouter' else 'serverSideRouter'
  'cord!utils/Future'
  'cord!utils/profiler/realProfiler'
  'dustjs-helpers'
], (Api, Behaviour, ServiceContainer, templateLoader, Widget, WidgetRepo,
    browserInit, Request, router, Future, pr, dust) ->


  patchFutureWithZone = ->
    # registry of bound zones associated with "zoneified" Future callbacks, need to correctly dequeue zone tasks on clear
    futureIds = {}
    idCounter = 0

    # patching Future.done, .fail and .finally to preserve zone chain for callbacks
    patchFnNames = ['done', 'fail', 'finally']
    for fnName in patchFnNames
      do (fnName) ->
        stateFilter = switch fnName
          when 'done' then 'rejected'
          when 'fail' then 'resolved'
          when 'finally' then 'always' # fake state, condition should always be true
        origFn = Future.prototype[fnName]

        Future.prototype[fnName] = (fn) ->
          if @_state != stateFilter
            if not @_zone_track_id_
              @_zone_track_id_ = idCounter++
              futureIds[@_zone_track_id_] =
                done: {}
                fail: {}
                finally: {}
            fn._zone_track_id_ = idCounter++
            futureIds[@_zone_track_id_][fnName][fn._zone_track_id_] = zone

            self = this
            patchedCallback = ->
              delete futureIds[self._zone_track_id_][fnName][fn._zone_track_id_]
              fn.apply(this, arguments)

            args = zone.constructor.bindArgumentsOnce([patchedCallback])
            origFn.apply(this, args)
          this


    # patching Future._clearDoneCallbacks and ._clearFailCallbacks
    #  to correctly dequeue zone tasks enqueued by Future.done or .fail
    patchFnNames = ['done', 'fail']
    for fnName in patchFnNames
      do (fnName) ->
        clearFnName = "_clear#{fnName.charAt(0).toUpperCase()}#{fnName.slice(1)}Callbacks"
        origFn = Future.prototype[clearFnName]

        Future.prototype[clearFnName] = ->
          if @_zone_track_id_
            _runClearTasks(futureIds[@_zone_track_id_][fnName])
            futureIds[@_zone_track_id_][fnName] = {}
          origFn.apply(this, arguments)


    # patching Future.clear to correctly dequeue all zone tasks associated with the Future instance
    origClear = Future.prototype.clear
    Future.prototype.clear = ->
      origClear.apply(this, arguments)
      if @_zone_track_id_
        _runClearTasks(futureIds[@_zone_track_id_].finally)
        delete @_zone_track_id_
        delete futureIds[@_zone_track_id_]


  _runClearTasks = (zoneMap) ->
    # DRY for Future clearing patched methods
    for id, boundZone of zoneMap
      boundZone.beforeTask(true)
      boundZone.dequeueTask()
      boundZone.afterTask(true)



  patchRequirejsWithZone = ->
    delegate = window.require
    if delegate
      window.require = ->
        if typeof arguments[1] == 'function'
          argIndex = 1
          callback = arguments[1]
          errback = arguments[2]
        else if typeof arguments[2] == 'function'
          argIndex = 2
          callback = arguments[2]
          errback = arguments[3]
        else
          argIndex = 0

        boundZone = if zone.parent and zone.parent.timerId then zone.parent else zone
        if not errback or argIndex == 0
          delegate.apply(this, zone.constructor.bindArgumentsOnceWithParentZone(arguments, boundZone))
        else
          arguments[argIndex] = boundZone.bind ->
            res = callback.apply(this, arguments)
            boundZone.dequeueTask(callback)
            # clear errback task
            boundZone.beforeTask(true)
            boundZone.dequeueTask()
            boundZone.afterTask(true)
            res

          arguments[argIndex + 1] = boundZone.bind ->
            res = errback.apply(this, arguments)
            boundZone.dequeueTask(errback)
            # clear callback task
            boundZone.beforeTask(true)
            boundZone.dequeueTask()
            boundZone.afterTask(true)
            res

          delegate.apply(this, arguments)

      window.requirejs = window.require


  ->
    patchFutureWithZone()

    # zone-patching of CordJS higher-level functions which use asynchronous non-patched NodeJS functions
    zone.constructor.patchFnWithParentZoneCallbacks Request.prototype, [
      'send'
    ]
    zone.constructor.patchFnWithParentZoneCallbacks Api.prototype, [
      'send'
    ]
    zone.constructor.patchFnWithCallbacks Widget.prototype, [
      'subscribeValueChange'
    ]

    patchRequirejsWithZone() if CORD_IS_BROWSER

    pr.patch(router, 'process', 0, 'url')
    pr.patch(Request.prototype, 'send', 1)
    pr.patch(Api.prototype, 'send', 1)
    pr.patch(Widget.prototype, 'renderTemplate', 1)
    pr.patch(Widget.prototype, 'resolveParamRefs', 1)
    pr.patch(Widget.prototype, 'getStructTemplate', 1)
    pr.patch(WidgetRepo.prototype, 'createWidget', 0)
    pr.patch(ServiceContainer.prototype, 'injectServices', 0)
    pr.patch(dust, 'render', 0)
    pr.patch(templateLoader, 'loadWidgetTemplate', 0)
    if CORD_IS_BROWSER
      pr.patch(window, 'require', 0)
      window.requirejs = window.require

      pr.patch(browserInit, 'init')
      pr.patch(router, 'navigate', 0)
      pr.patch(WidgetRepo.prototype, 'init', 0)
      pr.patch(WidgetRepo.prototype, 'smartTransitPage', 0)
      pr.patch(WidgetRepo.prototype, 'transitPage', 0)
      pr.patch(Widget.prototype, 'browserInit')
      pr.patch(Widget.prototype, 'initBehaviour')
      pr.patch(Behaviour.prototype, 'insertChildWidget', 0)

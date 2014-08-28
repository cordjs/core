define [
  'cord!Api'
  'cord!ServiceContainer'
  'cord!templateLoader'
  'cord!Widget'
  'cord!WidgetRepo'
  'cord!router/serverSideRouter'
  'cord!utils/Future'
  'cord!utils/profiler'
  'dustjs-helpers'
], (Api, ServiceContainer, templateLoader, Widget, WidgetRepo, router, Future, pr, dust) ->


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


  ->
    patchFutureWithZone()

    # zone-patching of cordjs higher-level functions which use asynchronous unpatched nodejs operations
    zone.constructor.patchFnWithCallbacks Api.prototype, [
      'send'
    ]
    zone.constructor.patchFnWithCallbacks Widget.prototype, [
      'subscribeValueChange'
    ]


    pr.patch(router, 'process', 0, 'url')
    pr.patch(Api.prototype, 'send', 1)
    pr.patch(Widget.prototype, 'renderTemplate', 1)
    pr.patch(Widget.prototype, 'resolveParamRefs', 1)
    pr.patch(Widget.prototype, 'getStructTemplate', 1)
    pr.patch(WidgetRepo.prototype, 'createWidget', 0)
    pr.patch(ServiceContainer.prototype, 'injectServices', 0)
    pr.patch(dust, 'render', 0)
    pr.patch(templateLoader, 'loadWidgetTemplate', 0)
    pr.patch(Future, 'require', 0)

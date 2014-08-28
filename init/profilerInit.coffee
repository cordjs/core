define [
  'cord!utils/profiler'
  'cord!Api'
  'cord!Widget'
  'cord!WidgetRepo'
  'cord!ServiceContainer'
  'cord!templateLoader'
  'cord!router/serverSideRouter'
  'cord!utils/Future'
  'dustjs-helpers'
], (pr, Api, Widget, WidgetRepo, ServiceContainer, templateLoader, router, Future, dust) ->


  patchFutureWithZone = ->
    idCounter = 0
    futureIds = {}

    origDone = Future.prototype.done
    Future.prototype.done = (fn) ->
      if @_state != 'rejected'
        if not @_zone_track_id_
          @_zone_track_id_ = idCounter++
          futureIds[@_zone_track_id_] =
            dones: {}
            fails: {}
            finallies: {}
        fn._zone_track_id_ = idCounter++
        futureIds[@_zone_track_id_].dones[fn._zone_track_id_] = zone

        self = this
        patchedCallback = ->
          delete futureIds[self._zone_track_id_].dones[fn._zone_track_id_]
          fn.apply(this, arguments)

        args = zone.constructor.bindArgumentsOnce([patchedCallback])
        origDone.apply(this, args)
      this


    origFail = Future.prototype.fail
    Future.prototype.fail = (fn) ->
      if @_state != 'resolved'
        if not @_zone_track_id_
          @_zone_track_id_ = idCounter++
          futureIds[@_zone_track_id_] =
            dones: {}
            fails: {}
            finallies: {}
        fn._zone_track_id_ = idCounter++
        futureIds[@_zone_track_id_].fails[fn._zone_track_id_] = zone

        self = this
        patchedCallback = ->
          delete futureIds[self._zone_track_id_].fails[fn._zone_track_id_]
          fn.apply(this, arguments)

        args = zone.constructor.bindArgumentsOnce([patchedCallback])
        origFail.apply(this, args)
      this


    origFinally = Future.prototype.finally
    Future.prototype.finally = (fn) ->
      if not @_zone_track_id_
        @_zone_track_id_ = idCounter++
        futureIds[@_zone_track_id_] =
          dones: {}
          fails: {}
          finallies: {}
      fn._zone_track_id_ = idCounter++
      futureIds[@_zone_track_id_].finallies[fn._zone_track_id_] = zone
      self = this

      patchedCallback = ->
        delete futureIds[self._zone_track_id_].finallies[fn._zone_track_id_]
        fn.apply(this, arguments)

      args = zone.constructor.bindArgumentsOnce([patchedCallback])
      origFinally.apply(this, args)


    clearDone = Future.prototype._clearDoneCallbacks
    Future.prototype._clearDoneCallbacks = ->
      if @_zone_track_id_
        for id, boundZone of futureIds[@_zone_track_id_].dones
          boundZone.beforeTask(true)
          boundZone.dequeueTask()
          boundZone.afterTask(true)
        futureIds[@_zone_track_id_].dones = {}
      clearDone.apply(this, arguments)


    clearFail = Future.prototype._clearFailCallbacks
    Future.prototype._clearFailCallbacks = ->
      if @_zone_track_id_
        for id, boundZone of futureIds[@_zone_track_id_].fails
          boundZone.beforeTask(true)
          boundZone.dequeueTask()
          boundZone.afterTask(true)
        futureIds[@_zone_track_id_].fails = {}
      clearFail.apply(this, arguments)


    origClear = Future.prototype.clear
    Future.prototype.clear = ->
      origClear.apply(this, arguments)
      if @_zone_track_id_
        for id, boundZone of futureIds[@_zone_track_id_].finallies
          boundZone.beforeTask(true)
          boundZone.dequeueTask()
          boundZone.afterTask(true)
        delete @_zone_track_id_
        delete futureIds[@_zone_track_id_]


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

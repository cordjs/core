define [
  'cord!errors'
  'cord!utils/Defer'
  'cord!utils/Future'
  'underscore'
], (errors, Defer, Future, _) ->

  class DeferAggregator

    defers: {}

    setWidgetParams: (widget, params) ->
      id = widget.ctx.id
      if @defers[id]?
        df = @defers[id]
        _.extend(df.params, params)
        for key, value of params
          if value == ':deferred'
            if not df.deferredParams[key]?
              df.promise.fork()
              df.deferredParams[key] = true
          else if df.deferredParams[key]?
            df.promise.resolve()
            df.deferredParams[key] = null
      else
        df =
          params: params
          promise: (new Future('deferAgregator')).fork()
          deferredParams: {}
        @defers[id] = df

        for key, value of params
          if value == ':deferred'
            df.deferredParams[key] = true
            df.promise.fork()

        Defer.nextTick ->
          df.promise.resolve()

        df.promise.done =>
          widget.setParamsSafe(df.params).catchIf (err) ->
            err instanceof errors.WidgetParamsRace
          .failAloud(widget.debug('DeferAggregator'))

          delete @defers[id]



  new DeferAggregator

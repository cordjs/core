define [
  'cord!errors'
  'cord!utils/Future'
  'asap/raw'
  'underscore'
], (errors, Future, asap, _) ->

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

        asap ->
          df.promise.resolve()

        df.promise.then =>
          widget.setParamsSafe(df.params).catchIf (err) ->
            err instanceof errors.WidgetParamsRace
          .failAloud(widget.debug('DeferAggregator'))

          delete @defers[id]
      return



  new DeferAggregator

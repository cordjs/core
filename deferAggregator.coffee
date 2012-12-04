define [
  'underscore'
], (_) ->

  class DeferAggregator

    defers: {}

    fireAction: (widget, action, params) ->
      id = widget.ctx.id
      if @defers[id]?[action]?
        _.extend @defers[id][action], params
      else
        @defers[id] = {} if not @defers[id]?
        @defers[id][action] = params
        setTimeout =>
          widget.fireAction action, @defers[id][action]
          delete @defers[id][action]
        , 0


  new DeferAggregator

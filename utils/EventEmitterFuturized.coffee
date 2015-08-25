define [
  'cord!utils/Future'
], (Future) ->

  class EventEmitterFuturized

    constructor: ->
      @__subscriptions = {}


    on: (event, callback) ->
      ###
      Registers a new callback for specified event
      ###
      (@__subscriptions[event] ?= []).push(callback)
      this


    off: (event, callback) ->
      @__subscriptions[event] = (@__subscriptions[event] ?= []).filter (v) -> v != callback
      this


    once: (event, callback) ->
      realCallback = (args...) =>
        result = callback.apply(null, args)
        @off(event, realCallback)
        result
      @on(event, realCallback)
      this


    emit: (event, params) ->
      Future.settle(
        for callback in (@__subscriptions[event] ?= [])
          Future.try -> callback.call(null, params)
      ).then (result) ->
        # Keep result rejected if any promise rejected
        for v in result
          if v.isRejected()
            throw v.reason()
        undefined # resolved promise to undefined

define [
  'cord!Behaviour'
], (Behaviour) ->

  class TimerListBehaviour extends Behaviour

    init: ->
      @widget.expandSlowestPath() if @widget.ctx.expandSlowest

define [
  'cord!Behaviour'
], (Behaviour) ->

  class TimerWithToolbarBehaviour extends Behaviour

    @events:
      'click .btn-slowest': -> @widget.expandSlowestPath()

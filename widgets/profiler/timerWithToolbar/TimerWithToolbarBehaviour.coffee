define [
  'cord!Behaviour'
], (Behaviour) ->

  class TimerWithToolbarBehaviour extends Behaviour

    @elements:
      '>.toolbar-buttons .btn-slowest': 'btnSlowest'

    @events:
      'click @btnSlowest': -> @widget.expandSlowestPath()
define [
  'cord!Behaviour'
], (Behaviour) ->

  class PanelBehaviour extends Behaviour

    @widgetEvents:
      timers: 'render'

    @events:
      'click .e-expand-slowest': -> @widget.expandSlowestPath()

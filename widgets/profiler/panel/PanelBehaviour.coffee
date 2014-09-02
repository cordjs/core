define [
  'cord!Behaviour'
], (Behaviour) ->

  class PanelBehaviour extends Behaviour

    @widgetEvents:
      timers: 'render'

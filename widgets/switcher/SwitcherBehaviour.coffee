define [
  'cord!Behaviour'
], (Behaviour) ->

  class SwitcherBehaviour extends Behaviour

    widgetEvents:
      'widgetType': 'render'

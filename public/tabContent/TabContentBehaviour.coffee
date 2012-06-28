define [
  '../Behaviour'
  'jquery'
], (Behaviour, $) ->

  class TabContentBehaviour extends Behaviour

    constructor: (widget) ->
      @widgetEvents =
        'activeTab': 'onActiveTabChange'
      super widget

    onActiveTabChange: =>
      console.log "reRenderTemplate"
      @render()
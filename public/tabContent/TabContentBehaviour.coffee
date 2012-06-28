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
      @widget.renderTemplate (err, output) =>
        if err then throw err
        $('#'+@widget.ctx.id).html output
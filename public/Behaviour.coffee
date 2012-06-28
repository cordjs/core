define [
  'postal'
], (postal) ->

  class Behaviour

    constructor: (widget) ->
      @widget = widget
      @id = widget.ctx.id
#      @widgetEvents = {}
      @_setupBindings()
      @_setupWidgetBindings()

    _setupBindings: ->
      console.log "setup bindings"
      # do nothing, should be overriden

    _setupWidgetBindings: ->
      for fieldName, callback of @widgetEvents
        postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: @[callback]

    render: ->
      @widget.renderTemplate (err, output) =>
        if err then throw err
        $('#'+@widget.ctx.id).html output
        @_setupBindings()
define [
  'postal'
], (postal) ->

  class Behaviour

    constructor: (widget) ->
      @_widgetSubscriptions = []
      @widget = widget
      @id = widget.ctx.id
#      @widgetEvents = {}
      @_setupBindings()
      @_setupWidgetBindings()

    clean: ->
      subscription.unsubscribe() for subscription in @_widgetSubscriptions
      @_widgetSubscriptions = []

    _setupBindings: ->
      console.log "setup bindings", @constructor.name
      # do nothing, should be overriden

    _setupWidgetBindings: ->
      for fieldName, callback of @widgetEvents
        subscription = postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: @[callback]
        @_widgetSubscriptions.push subscription

    render: ->
      @widget.renderTemplate (err, output) =>
        if err then throw err
        $('#'+@widget.ctx.id).html output
        @widget.browserInit()
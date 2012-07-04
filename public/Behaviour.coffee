define [
  'jquery'
  'postal'
], ($, postal) ->

  class Behaviour

    tag: 'div'

    constructor: (widget) ->
      @_widgetSubscriptions = []
      @widget = widget
      @id = widget.ctx.id
#      @widgetEvents = {}
      @_setupBindings()
      @_setupWidgetBindings()

      @el  = document.createElement(@tag) unless @el
      @el  = $(@el)
      @$el = @el

      @events = @constructor.events unless @events
      @delegateEvents(@events) if @events

    $: (selector) ->
      $(selector, @el)

    delegateEvents: (events) ->
      console.log 'delegate', events
      for key, method of events

        if typeof(method) is 'function'
        # Always return true from event handlers
          method = do (method) => =>
            method.apply(this, arguments)
            true
        else
          unless @[method]
            throw new Error("#{method} doesn't exist")

          method = do (method) => =>
            @[method].apply(this, arguments)
            true
        console.log @el

        match      = key.match(/^(\S+)\s*(.*)$/)
        eventName  = match[1]
        selector   = match[2]

        if selector is ''
          @el.bind(eventName, method)
        else
          @el.delegate(selector, eventName, method)

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
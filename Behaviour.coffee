define [
  'jquery'
  'postal'
], ($, postal) ->

  class Behaviour

    rootEls: null

    constructor: (widget) ->
      @_widgetSubscriptions = []
      @widget = widget
      @id = widget.ctx.id

      @el  = $('#' + @widget.ctx.id )
      @$el = @el

      @rootEls = []
      @rootEls.push @el if @el.length == 1

      if widget.ctx[':inlines']?
        @rootEls.push $('#'+info.id) for inlineName, info of widget.ctx[':inlines']

      @events       = @constructor.events unless @events
      @widgetEvents = @constructor.widgetEvents unless @widgetEvents
      @elements     = @constructor.elements unless @elements

      @delegateEvents(@events)          if @events
      @initWidgetEvents(@widgetEvents)  if @widgetEvents
      @refreshElements()                if @elements


    $: (selector) ->
      $(selector, @el)

    delegateEvents: (events) ->
      for key, method of events

        method     = @_getMethod method
        match      = key.match(/^(\S+)\s*(.*)$/)
        eventName  = match[1]
        selector   = match[2]

        if selector is ''
          $el.on(eventName, method) for $el in @rootEls
        else
          $el.on(eventName, selector, method) for $el in @rootEls

    initWidgetEvents: (events) ->
      for fieldName, method of events
        subscription = postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: @_getMethod method
        @_widgetSubscriptions.push subscription

    _getMethod: (method) ->
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
      method

    refreshElements: ->
      for key, value of @elements
        @[value] = @$(key)

    clean: ->
      subscription.unsubscribe() for subscription in @_widgetSubscriptions
      @_widgetSubscriptions = []
      @widget = null
      @el.off()#.remove()
      @el = null
      @$el = null

    html: (element) ->
      @el.html(element.el or element)
      @refreshElements()
      @el

    append: (elements...) ->
      elements = (e.el or e for e in elements)
      @el.append(elements...)
      @refreshElements()
      @el

    appendTo: (element) ->
      @el.appendTo(element.el or element)
      @refreshElements()
      @el

    prepend: (elements...) ->
      elements = (e.el or e for e in elements)
      @el.prepend(elements...)
      @refreshElements()
      @el

    replace: (element) ->
      [previous, @el] = [@el, $(element.el or element)]
      previous.replaceWith(@el)
      @delegateEvents(@events) if @events
      @refreshElements()
      @el

    render: ->
      # renderTemplate will clean this behaviour, so we must save links...
      widget = @widget
      $el = @$el
      widget.renderTemplate (err, out) =>
        if err then throw err
        $el.html out
        $el.on 'DOMNodeInserted', =>
          widget.browserInit()

    renderInline: (name) ->
      ###
      Re-renders inline with the given name
      @param String name inline's name to render
      ###

      @widget.renderInline name, (err, out) =>
        if err then throw err
        id = @widget.ctx[':inlines'][name].id
        $el = $('#'+id)
        $el.html out
#        $el.on 'DOMNodeInserted', =>
#          @widget.browserInit()

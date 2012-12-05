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

      setTimeout =>
        postal.publish "widget.#{ @id }.behaviour.init", {}
      , 0

    $: (selector) ->
      $(selector, @el)

    delegateEvents: (events) ->
      for key, method of events

        method     = @_getMethod method
        match      = key.match(/^(\S+)\s*(.*)$/)
        eventName  = match[1]
        selector   = match[2]

        do (method, eventName, selector) =>
          if selector is ''
            if eventName == 'init' || eventName == 'destroy'
              subscription = postal.subscribe
                topic: "widget.#{ @id }.behaviour.#{ eventName }"
                callback: ->
                  method()
                  subscription.unsubscribe()
              @_widgetSubscriptions.push subscription
            else
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
      postal.publish "widget.#{ @id }.behaviour.destroy", {}
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
      console.log "#{ @widget.debug 'defer-re-render' }"

      @defer 'render', =>
        if @widget?
          console.log "#{ @widget.debug 're-render' }"
          # renderTemplate will clean this behaviour, so we must save links...
          widget = @widget
          $el = @$el
          widget.renderTemplate (err, out) ->
            if err then throw err

            oneMore = false
            wait = ->
              oneMore = false
              setTimeout ->
                if not oneMore
                  $el.off 'DOMNodeInserted'
                  widget.browserInit()
              , 0

            $el.on 'DOMNodeInserted', ->
              oneMore = true
              wait()
            $el.html out


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


    renderNewWidget: (widget, params, callback) ->
      ###
      Renders (via show method) the given widget with the given params, inserts it into DOM and initialtes.
      Returns jquery-object referring to the widget's root element via callback argument.
      @param Widget widget widget object
      @param Object params key-value params for the widget default action
      @param Function(jquery) callback callback which is called with the resulting jquery element and created object of widget
      ###
      widget.show params, (err, out) ->
        if err then throw err
        tmpId = _.uniqueId '__cord_special_tmp_background_creation_container'
        $tmp = $('#'+tmpId)
        $tmp = $("<div style=\"display:none\" id=\"#{ tmpId }\"></div>").appendTo('body') if $tmp.length == 0
        $tmp.one 'DOMNodeInserted', ->
          widget.browserInit()
          callback $('#'+widget.ctx.id), widget
          $tmp.remove()
        $tmp.html widget.renderRootTag(out)


    initChildWidget: (type, params, callback) ->
      ###
      Creates and initiates new child widget with the given type and params.
      Returns jquery-object referring to the widget's root element via callback argument for further inserting the
      widget to the right place in the DOM.
      @param String type widget type in canonical format (absolute or in context of the current widget)
      @param Object params key-value params for the widget default action
      @param Function(jquery) callback callback which is called with the resulting jquery element and created object of widget
      ###
      @widget.createChildWidget type, (newWidget) =>
        @renderNewWidget newWidget, params, callback


    defer: (id, fn) ->
      @defers ?= {}
      if @defers[id]?
        @defers[id]++
      else
        @defers[id] = 1
        setTimeout =>
          fn()
          delete @defers[id]
        , 0


    getServiceContainer: ->
      @widget.getServiceContainer()

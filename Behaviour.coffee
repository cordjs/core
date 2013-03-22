define [
  'cord!utils/Defer'
  'cord!utils/DomHelper'
  'jquery'
  'postal'
], (Defer, DomHelper, $, postal) ->

  class Behaviour

    rootEls: null

    constructor: (widget, $domRoot) ->
      ###
      @param Widget widget
      @param (optional)jQuery $domRoot prepared root element of the widget or of some widget's parent
      ###
      @_widgetSubscriptions = []
      @widget = widget
      @id = widget.ctx.id

      if $domRoot
        if $domRoot.attr('id') == @id
          @el = $domRoot
        else
          @el = $('#' + @id, $domRoot)
      else
        @el  = $('#' + @id)

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

      Defer.nextTick =>
        postal.publish "widget.#{ @id }.behaviour.init", {}


    $: (selector) ->
      ###
      Creates jQuery object with the given selector in the context of this widget.
      Multiple root element of the widget (when there are several inlines) are also supported by aggregation or results.
      @param String selector jquery selector
      @return jQuery
      ###
      if @rootEls.length == 1
        $(selector, @rootEls[0])
      else if @rootEls.length
        result = $()
        result = result.add(selector, el) for el in @rootEls
        result
      else
        $(selector)


    addSubscription: (subscriptionDef)->
      @_widgetSubscriptions.push subscriptionDef


    delegateEvents: (events) ->
      for key, method of events

        method     = @_getEventMethod(method)
        match      = key.match(/^(\S+)\s*(.*)$/)
        eventName  = match[1]
        selector   = match[2]

        do (method) =>
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
            if eventName == 'scroll'
              $(selector, $el).on(eventName, method) for $el in @rootEls
            else
              $el.on(eventName, selector, method) for $el in @rootEls


    initWidgetEvents: (events) ->
      for fieldName, method of events
        subscription = postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: @_getWidgetEventMethod(method)
        @_widgetSubscriptions.push(subscription)


    _getEventMethod: (method) ->
      m = @_getHandlerFunction(method)
      =>
        m.apply(this, arguments) #if not @widget.isSentenced()
        true


    _getWidgetEventMethod: (method) ->
      m = @_getHandlerFunction(method)
      => m.apply(this, arguments) if not @widget.isSentenced() and arguments[0].value != ':deferred'


    _getHandlerFunction: (method) ->
      if typeof(method) is 'function'
        result = method
      else
        throw new Error("#{method} doesn't exist") unless @[method]
        result = @[method]
      result


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
#      console.log "#{ @widget.debug 'defer-re-render' }"
      @widget.sentenceChildrenToDeath()

      @defer 'render', =>
        if @widget?
          console.log "#{ @widget.debug 're-render' }"
          # renderTemplate will clean this behaviour, so we must save links...
          widget = @widget
          widget.renderTemplate (err, out) ->
            if err then throw err
            DomHelper.insertHtml widget.ctx.id, out, ->
              widget.browserInit()
#            $newWidgetRoot = $(widget.renderRootTag(out))
#            widget.browserInit($newWidgetRoot)
#            $('#'+widget.ctx.id).replaceWith($newWidgetRoot)


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
        $el = $(widget.renderRootTag(out))
        widget.browserInit($el)
        callback($el, widget)


    initChildWidget: (type, name, params, callback) ->
      ###
      Creates and initiates new child widget with the given type and params.
      Returns jquery-object referring to the widget's root element via callback argument for further inserting the
      widget to the right place in the DOM.
      @param String type widget type in canonical format (absolute or in context of the current widget)
      @param (optional)String name optional name for the new widget
      @param Object params key-value params for the widget default action
      @param Function(jquery) callback callback which is called with the resulting jquery element and created object of widget
      ###
      if _.isObject(name)
        callback = params
        params = name
        name = null

      @widget.createChildWidget type, name, (newWidget) =>
        @renderNewWidget newWidget, params, callback


    defer: (id, fn) ->
      @defers ?= {}
      if @defers[id]?
        @defers[id]++
      else
        @defers[id] = 1
        Defer.nextTick =>
          fn()
          delete @defers[id]


    getServiceContainer: ->
      @widget.getServiceContainer()


    debug: (method) ->
      ###
      Return identification string of the current widget for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @widget.getPath() }Behaviuor(#{ @widget.ctx.id })#{ methodStr }"

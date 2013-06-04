define [
  'cord!Model'
  'cord!utils/Defer'
  'jquery'
  'postal'
], (Model, Defer, $, postal) ->

  class Behaviour

    # jQuery aggregate of all DOM-roots of the widget
    # (widget can have multiple DOM-roots when it has several inline-blocks)
    $rootEls: null

    _widgetSubscriptions: null
    _modelBindings: null
    _eventCursors: null

    constructor: (widget, $domRoot) ->
      ###
      @param Widget widget
      @param (optional)jQuery $domRoot prepared root element of the widget or of some widget's parent
      ###
      @_widgetSubscriptions = []
      @_modelBindings = {}
      @_eventCursors = {}

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

      @$rootEls = if @el.length == 1 then @el else $()

      if widget.ctx[':inlines']?
        @$rootEls = @$rootEls.add('#'+info.id, $domRoot) for inlineName, info of widget.ctx[':inlines']

      @events       = @constructor.events unless @events
      @widgetEvents = @constructor.widgetEvents unless @widgetEvents
      @elements     = @constructor.elements unless @elements

      @delegateEvents(@events)          if @events
      @initWidgetEvents(@widgetEvents)  if @widgetEvents
      @refreshElements()                if @elements

      Defer.nextTick => @initiateInit()


    initiateInit: ->
      #Protection from Defer.nextTick => @init()
      #TODO: cleanup timeouts on destruction
      if !@widget
        return
      @init()


    init: ->
      postal.publish "widget.#{ @id }.behaviour.init", {}


    $: (selector) ->
      ###
      Creates jQuery object with the given selector in the context of this widget.
      Multiple root element of the widget (when there are several inlines) are also supported transparently.
      @param String selector jquery selector
      @return jQuery
      ###
      if @$rootEls.length > 0
        $(selector, @$rootEls)
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
              @$rootEls.on(eventName, method)
          else
            # special helper selector ##
            # ##someId is replaced by #{widgets id}-someId
            # in widget template it should look like id="{id}-someId"
            if selector.substr(0, 2) == '##'
              selector = '#' + @widget.ctx.id + '-' + selector.substr(2)

            if eventName == 'scroll'
              # scroll event is not bubbling up, so it have to be bound without event delegation feature
              # right to the element
              $(selector, @$rootEls).on(eventName, method)
            else
              @$rootEls.on(eventName, selector, method)


    initWidgetEvents: (events) ->
      for fieldName, method of events
        onChangeMethod = @_getWidgetEventMethod(fieldName, method)

        subscription = postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: onChangeMethod
        @_widgetSubscriptions.push(subscription)

        @_registerModelBinding(@widget.ctx[fieldName], fieldName, onChangeMethod)


    _getEventMethod: (method) ->
      m = @_getHandlerFunction(method)
      =>
        m.apply(this, arguments) #if not @widget.isSentenced()
        true


    _getWidgetEventMethod: (fieldName, method) ->
      m = @_getHandlerFunction(method)
      onChangeMethod = =>
        data = arguments[0]
        duplicate = false
        if data.cursor
          if @_eventCursors[data.cursor]
            delete @_eventCursors[data.cursor]
            duplicate = true
          else
            @_eventCursors[data.cursor] = true
        if not @widget.isSentenced() and data.value != ':deferred' and not data.initMode and not duplicate
          @_registerModelBinding(data.value, fieldName, onChangeMethod)
          m.apply(this, arguments)


    _registerModelBinding: (value, fieldName, onChangeMethod) ->
      if @_modelBindings[fieldName]?
        mb = @_modelBindings[fieldName]
        if value != mb.model
          mb.subscription.unsubscribe() if mb.subscription?
          delete @_modelBindings[fieldName]

      if value instanceof Model and not (@_modelBindings[fieldName]? and value == mb.model)
        @_modelBindings[fieldName] ?= {}
        @_modelBindings[fieldName].model = value
        @_modelBindings[fieldName].subscription = value.on 'change', (model) =>
          onChangeMethod
            name: fieldName
            value: model
            oldValue: value


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

      for name, mb of @_modelBindings
        mb.subscription?.unsubscribe()
      @_modelBindings = {}

      @widget = null
      @el.off()#.remove()
      @el = @$el = null


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
      ###
      Fully re-render and replace all widget's contents by killing all child widgets and re-rendering own template.
      Works using defer async in order to collapse several simultaineous calls of render into one.
      ###
      @widget.sentenceChildrenToDeath()
      @defer 'render', =>
        if @widget?
          console.log "#{ @widget.debug 're-render' }"
          # renderTemplate will clean this behaviour, so we must save links...
          widget = @widget
          widget.renderTemplate (err, out) ->
            if err then throw err
            $newWidgetRoot = $(widget.renderRootTag(out))
            widget.browserInit($newWidgetRoot).done ->
              $('#'+widget.ctx.id).replaceWith($newWidgetRoot)


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
      @param Object params key-value params for the widget
      @param Function(jquery) callback callback which is called with the resulting jquery element and created object of widget
      ###
      if (parentWidget = @widget)?
        widget.show params, (err, out) ->
          if err then throw err
          $el = $(widget.renderRootTag(out))
          widget.browserInit($el).done ->
            callback($el, widget) if not parentWidget.isSentenced()


    initChildWidget: (type, name, params, callback) ->
      ###
      Creates and initiates new child widget with the given type and params.
      Returns jquery-object referring to the widget's root element via callback argument for further inserting the
      widget to the right place in the DOM.
      @param String type widget type in canonical format (absolute or in context of the current widget)
      @param (optional)String name optional name for the new widget
      @param Object params key-value params for the widget
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

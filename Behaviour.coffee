define [
  'cord!Model'
  'cord!utils/Defer'
  'cord!utils/DomHelper'
  'cord!utils/DomInfo'
  'jquery'
  'postal'
], (Model, Defer, DomHelper, DomInfo, $, postal) ->

  class Behaviour

    # jQuery aggregate of all DOM-roots of the widget
    # (widget can have multiple DOM-roots when it has several inline-blocks)
    $rootEls: null

    _widgetSubscriptions: null
    _modelBindings: null

    constructor: (widget, $domRoot) ->
      ###
      @param Widget widget
      @param (optional)jQuery $domRoot prepared root element of the widget or of some widget's parent
      ###
      @_widgetSubscriptions = []
      @_modelBindings = {}

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

      @elements     = @constructor.elements unless @elements
      @elements     = @elements() if _.isFunction @elements

      @_elementSelectors = {} if @elements # needed to support '@element'-like selectors for events

      @events       = @constructor.events unless @events
      @events       = @events() if _.isFunction @events

      @widgetEvents = @constructor.widgetEvents unless @widgetEvents
      @widgetEvents = @widgetEvents() if _.isFunction @widgetEvents

      @refreshElements()                if @elements
      @delegateEvents(@events)          if @events
      @initWidgetEvents(@widgetEvents)  if @widgetEvents
      @_callbacks = []

      @init()
      if @show?
        @widget.shown().done @getCallback =>
          @show()


    init: ->


    destroy: ->


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


    addSubscription: (subscription, callback = null) ->
      if callback and _.isString subscription
        subscription = postal.subscribe
          topic: subscription
          callback: callback
      @_widgetSubscriptions.push subscription
      subscription


    getCallback: (callback) =>
      ###
      Register callback and clear it in case of object destruction or clearCallbacks invocation
      Need to be used, when reference to the widget object (@) is used inside a callback, for instance:
      api.get Url, Params, @getCallback (result) =>
        @ctx.set 'apiResult', result
      ###
      that = this
      makeSafeCallback = (callback) ->
        result = -> callback.apply(null, arguments) if not result.cleared and not that.widget.isSentenced()
        result.cleared = false
        result

      safeCallback = makeSafeCallback(callback)
      @_callbacks.push safeCallback
      safeCallback


    clearCallbacks: ->
      callback.cleared = true for callback in @_callbacks
      @_callbacks = []


    delegateEvents: (events) ->
      for key, method of events

        method     = @_getEventMethod(method)
        match      = key.match(/^(\S+)\s*(.*)$/)
        eventName  = match[1]
        selector   = match[2]

        do (method, selector) =>
          if selector is ''
            @$rootEls.on(eventName, method)
          else
            # special helper selector ##
            # ##someId is replaced by #{widgets id}-someId
            # in widget template it should look like id="{id}-someId"
            if selector.substr(0, 2) == '##'
              selector = '#' + @widget.ctx.id + '-' + selector.substr(2)

            # support for @elementName like selectors
            if selector[0] == '@' and this[selector.substr(1)]
              selector = @_elementSelectors[selector.substr(1)]

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
        ctxVersionBorder = @widget._behaviourContextBorderVersion
        # if data.version is undefined than it's model-emitted event and need not version check
        versionOk = (not ctxVersionBorder? or not data.version? or data.version > ctxVersionBorder)
        if not @widget.isSentenced() and data.value != ':deferred' and versionOk
          duplicate = false
          if data.cursor
            if @widget._eventCursors[data.cursor]
              delete @widget._eventCursors[data.cursor]
              duplicate = true
            else
              @widget._eventCursors[data.cursor] = true
          if not duplicate
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
        this[value] = @$(key)
        @_elementSelectors[value] = key


    clean: ->
      @destroy()

      subscription.unsubscribe() for subscription in @_widgetSubscriptions
      @_widgetSubscriptions = []

      for name, mb of @_modelBindings
        mb.subscription?.unsubscribe()
      @_modelBindings = {}

      @widget = null
      @el.off()
      @el = @$el = null

      @clearCallbacks()


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
          # renderTemplate will clean this behaviour, so we must save links...
          widget = @widget
          $rootEl = @el
          domInfo = new DomInfo(@debug('render'))
          # harakiri: this is need to avoid interference of subsequent async calls of the @render() for the same widget
          @widget._cleanBehaviour()
          widget.renderTemplate(domInfo).then (out) ->
            $newWidgetRoot = $(widget.renderRootTag(out))
            domInfo.setDomRoot($newWidgetRoot)
            widget.browserInit($newWidgetRoot).then ->
              DomHelper.replaceNode($rootEl, $newWidgetRoot)
            .then ->
              domInfo.markShown()
              widget.markShown()
              widget.emit 're-render.complete'
          .failAloud()


    renderInline: (name) ->
      ###
      Re-renders inline with the given name
      @param String name inline's name to render
      @deprecated inlines re-rendering should be performed by render() method
      ###
      @widget._behaviourContextBorderVersion = null
      @widget._resetWidgetReady()
      domInfo = new DomInfo(@debug('renderInline'))
      @widget.renderInline(name, domInfo).failAloud().done (out) =>
        $newInlineRoot = $(@widget.renderInlineTag(name, out))
        domInfo.setDomRoot($newInlineRoot)
        id = @widget.ctx[':inlines'][name].id
        $oldInlineRoot = $('#'+id)
        DomHelper.replaceNode($oldInlineRoot, $newInlineRoot).done =>
          domInfo.markShown()
          @widget.browserInit()


    renderNewWidget: (widget, params, callback) ->
      ###
      Renders (via show method) the given widget with the given params, inserts it into DOM and initialtes.
      Returns jquery-object referring to the widget's root element via callback argument.
      @param Widget widget widget object
      @param Object params key-value params for the widget
      @param Function(jquery) callback callback which is called with the resulting jquery element and created object of widget
      ###
      if (parentWidget = @widget)?
        domInfo = new DomInfo("#{ @debug('renderNewWidget') } -> #{ widget.debug() }")
        widget.show(params, domInfo).failAloud().done (out) ->
          $el = $(widget.renderRootTag(out))
          domInfo.setDomRoot($el)
          domInfo.domInserted().when(widget.shown())
          widget.browserInit($el).done ->
            callback($el, widget, domInfo) if not parentWidget.isSentenced()


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


    dropChildWidget: (widget) ->
      @widget.dropChild(widget.ctx.id)


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
      "#{ @widget.getPath() }Behaviour(#{ @widget.ctx.id })#{ methodStr }"

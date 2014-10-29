define [
  'cord!errors'
  'cord!Model'
  'cord!utils/Defer'
  'cord!utils/DomHelper'
  'cord!utils/DomInfo'
  'cord!utils/Future'
  'cord!utils/profiler/profiler'
  'cord!Module'
  'jquery'
  'postal'
], (errors, Model, Defer, DomHelper, DomInfo, Future, pr, Module, $, postal) ->

  checkIsSentenced = (widget, message = '') ->
    ###
    Utility DRY function to check if the given widget is sentenced and trow special exception about it.
    @param {Widget} widget the checking widget
    @param optional{String} message additional message to be included to the exception
    @throws Error
    ###
    if widget.isSentenced()
      throw new errors.WidgetSentenced(
        "Widget #{widget.debug()} is sentenced!#{ if message then " (#{message})" else ''}"
      )


  class Behaviour extends Module

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

      pr.timer "#{@constructor.name}::init", =>
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


    addClass: (value) ->
      ###
      Adds the specified class(es) to the root element(s) of the widget.
      This change will be preserved on the widget re-render.
      @param String value One or more space-separated CSS classes
      ###
      @_clsPrepare value, (classes, ctx) ->
        addClasses = _.difference(classes, ctx.__cord_dyn_classes__)
        @_clsAdd(addClasses, ctx)


    removeClass: (value) ->
      ###
      Removes the specified class(es) from the root element(s) of the widget.
      This change will be preserved on the widget re-render.
      @param String value One or more space-separated CSS classes
      ###
      @_clsPrepare value, (classes, ctx) ->
        removeClasses = _.intersection(classes, ctx.__cord_dyn_classes__)
        @_clsRemove(removeClasses, ctx)


    toggleClass: (value, state) ->
      ###
      Adds or removes one or more classes from the root element(s) of the widget,
       depending on either the class's presence or the value of the `state` argument.
      If the state value is not set the given classes existence is inverted.
      This change will be preserved on the widget re-render.
      @param String value One or more space-separated CSS classes
      @param Boolean state A boolean value to determine whether the class should be added or removed
      ###
      if state?
        state = !!state
        if state
          @addClass(value)
        else
          @removeClass(value)
      else
        @_clsPrepare value, (classes, ctx) ->
          addClasses = _.difference(classes, ctx.__cord_dyn_classes__)
          removeClasses = _.intersection(classes, ctx.__cord_dyn_classes__)
          @_clsRemove(removeClasses, ctx)
          @_clsAdd(addClasses, ctx)


    _clsPrepare: (value, cb) ->
      ###
      DRY for (add|remove|toggle)Class
      ###
      if @widget
        ctx = @widget.ctx
        ctx.__cord_dyn_classes__ ?= []
        classes = value.split(/\s/).filter((x) -> x != '')
        # calling in the context of the behaviour to avoid necessity of using fat arrow
        cb.call(this, classes, ctx)


    _clsAdd: (addClasses, ctx) ->
      ###
      DRY for (add|toggle)Class
      ###
      ctx.__cord_dyn_classes__ = ctx.__cord_dyn_classes__.concat(addClasses)
      root = if @el.length == 1 then @el else @$rootEls
      root.addClass(addClasses.join(' ')) if addClasses.length > 0


    _clsRemove: (removeClasses, ctx) ->
      ###
      DRY for (remove|toggle)Class
      ###
      ctx.__cord_dyn_classes__ = _.difference(ctx.__cord_dyn_classes__, removeClasses)
      root = if @el.length == 1 then @el else @$rootEls
      root.removeClass(removeClasses.join(' ')) if removeClasses.length > 0


    addSubscription: (subscription, callback = null) ->
      if callback and _.isString subscription
        subscription = postal.subscribe
          topic: subscription
          callback: callback
      @_widgetSubscriptions.push subscription
      subscription


    getCallback: (callback) ->
      ###
      Register callback and clear it in case of object destruction or clearCallbacks invocation
      Need to be used, when reference to the widget object (@) is used inside a callback, for instance:
      api.get Url, Params, @getCallback (result) =>
        @ctx.set 'apiResult', result
      ###
      that = this
      makeSafeCallback = (callback) ->
        result = -> callback.apply(null, arguments) if not result.cleared and that.widget and not that.widget.isSentenced()
        result.cleared = false
        result

      safeCallback = makeSafeCallback(callback)
      @_callbacks.push safeCallback
      safeCallback


    clearCallbacks: ->
      callback.cleared = true for callback in @_callbacks
      @_callbacks = []


    delegateEvents: (events) ->
      if typeof window.zone != 'undefined'
        tmpZone = window.zone
        window.zone = tmpZone.constructor.rootZone
      for key, method of events

        method     = @_getEventMethod(method, key)
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
              root = if @el.length == 1 then @el else @$rootEls
              root.on(eventName, selector, method)
      if typeof window.zone != 'undefined'
        window.zone = tmpZone


    initWidgetEvents: (events) ->
      for fieldName, method of events
        onChangeMethod = @_getWidgetEventMethod(fieldName, method)

        subscription = postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: onChangeMethod
        @_widgetSubscriptions.push(subscription)

        @_registerModelBinding(@widget.ctx[fieldName], fieldName, onChangeMethod)


    _getEventMethod: (method, eventDesc) ->
      m = @_getHandlerFunction(method)
      that = this
      ->
        origArgs = arguments
        pr.timer "#{that.constructor.__name}::DOM('#{eventDesc}')", ->
          m.apply(that, origArgs) if that.widget and not that.widget.isSentenced()
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


    render: ->
      ###
      Fully re-renders and replaces all widget's contents by killing all child widgets and re-rendering own template.
      Works using defer async in order to collapse several simultaneous calls of render into one.
      @return Future[Behaviour] new behaviour instance
      ###
      @widget.sentenceChildrenToDeath()
      # re-render shouldn't be performed before the widget is shown due to possibility of wrong DOM root element
      #  state and replacing the DOM node in wrong place after re-render
      # this is pretty dangerous change and should attract attention when re-render isn't performed when it should be
      @widget.shown().then =>
        if not @_renderAggregatePromise?
          @_renderAggregatePromise = Future.single(@debug('renderAggregate'))
          Defer.nextTick =>
            @_renderAggregatePromise.when(@_render0())
            @_renderAggregatePromise = null
        @_renderAggregatePromise
      .catchIf (err) ->
        err instanceof errors.WidgetDropped
      .failAloud(@debug('render'))


    _render0: ->
      ###
      Actually re-render code. Should be used only from public render() method.
      ###
      if @widget?
        # renderTemplate will clean this behaviour, so we must save links...
        widget = @widget
        $rootEl = @el
        domInfo = new DomInfo(@debug('render'))
        # harakiri: this is need to avoid interference of subsequent async calls of the @render() for the same widget
        widget._cleanBehaviour()
        # dirty hack to prevent interfered browserInit() triggered by concurrently running Widget::inject()
        widget._delayedRender = true
        widget.renderTemplate(domInfo).then (out) ->
          $newWidgetRoot = $(widget.renderRootTag(out))
          domInfo.setDomRoot($newWidgetRoot)
          # unlocking flag to allow browserInit to proceed (see comment above)
          widget._delayedRender = false
          widget.browserInit($newWidgetRoot).then ->
            $newWidgetRoot.attr('style', $rootEl.attr('style'))
            DomHelper.replace($rootEl, $newWidgetRoot)
          .then ->
            domInfo.markShown()
            widget.markShown()
            widget.emit 're-render.complete'
            widget.behaviour
      else
        Future.rejected(new Error("Behaviour [#{@constructor.__name}] is already cleaned!"))


    renderInline: (name) ->
      ###
      Re-renders inline with the given name
      @param String name inline's name to render
      @deprecated inlines re-rendering should be performed by render() method
      ###
      @widget._behaviourContextBorderVersion = null
      @widget._resetWidgetReady()
      domInfo = new DomInfo(@debug('renderInline'))
      @widget.renderInline(name, domInfo).then (out) =>
        @widget.renderInlineTag(name, out)
      .then (wrappedOut) =>
        $newInlineRoot = $(wrappedOut)
        domInfo.setDomRoot($newInlineRoot)
        id = @widget.ctx[':inlines'][name].id
        $oldInlineRoot = $('#'+id)
        DomHelper.replace($oldInlineRoot, $newInlineRoot).then =>
          domInfo.markShown()
          @widget.browserInit()
      .failAloud(@debug('renderInline'))


    _renderNewWidget: (widget, params) ->
      ###
      Renders (via show method) the given widget with the given params, inserts it into DOM and initialtes.
      Returns jquery-object referring to the widget's root element via callback argument.
      @param Widget widget widget object
      @param Object params key-value params for the widget
      @return Future[jQuery] jQuery element of the created widget
      ###
      domInfo = new DomInfo("#{ @debug('renderNewWidget') } -> #{ widget.debug() }")
      widget.show(params, domInfo).then (out) ->
        checkIsSentenced(widget, 'after widget.show')
        $el = $(widget.renderRootTag(out))
        domInfo.setDomRoot($el)
        domInfo.domInserted().when(widget.shown())
        widget.browserInit($el).then ->
          checkIsSentenced(widget, 'after browserInit')
          $el


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

      try
        checkIsSentenced(@widget)
        @widget.createChildWidget(type, name).then (newWidget) =>
          checkIsSentenced(newWidget, 'before _renderNewWidget')
          @_renderNewWidget(newWidget, params).done ($el) ->
            callback?($el, newWidget)
          .then ($el) ->
            [[$el, newWidget]]
      catch err
        Future.rejected(err)


    insertChildWidget: (type, params = {}) ->
      ###
      Creates and correctly inserts a new child widget with the given params into the given place in the DOM.
      By default the root element of the newly created widget is appended to the end of the root element of this widget.
      Unlike `initChildWidget()` this method correctly performs `markShown()` for the inserted widget.
      @param {String} type widget type in canonical format (absolute or in context of the current widget)
      @param (optional){Object} params new widget's params and special positioning params
                                       Positioning params:
                                        ':position': 'append'(default)|'prepend'|'replace'
                                        ':context': DOM (jQuery) element into which should be inserted
                                                                           or which should be replaced
                                                    default - root element of this widget
      @return Future[Array[jQuery, Widget]]
      ###
      result = Future.single(@debug("insertChildWidget -> #{type}"))

      widgetParams = {}
      name = undefined
      insertPosition = 'append'
      insertContext = @el
      for key, val of params
        switch key
          when 'name'      then name = val
          when ':position' then insertPosition = val
          when ':context'  then insertContext = val
          else widgetParams[key] = val

      if insertPosition == 'replace' and insertContext == @el
        return Future.rejected(new Error("Child widget cannot replace parent\'s root element (#{@debug()})!"))

      @initChildWidget(type, name, widgetParams).spread ($el, newWidget) ->
        (switch insertPosition
          when 'append' then DomHelper.append(insertContext, $el)
          when 'prepend' then DomHelper.prepend(insertContext, $el)
          when 'replace' then DomHelper.replace(insertContext, $el)
          else throw new Error("Invalid insert position: #{insertPosition}!")
        ).then ->
          newWidget.markShown()
          [[$el, newWidget]]
      .then (res) -> result.resolve(res)
      .catch (err) ->
        result.reject(err)
        # preventing reporting of unhandled rejection in case of fast page switching
        result.failOk() if err instanceof errors.WidgetSentenced

      result


    dropChildWidget: (widget) ->
      @widget.dropChild(widget.ctx.id)


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

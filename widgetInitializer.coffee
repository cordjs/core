`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'postal'
], (postal) ->

  requireFunction = if window? then require else requirejs

  class WidgetInitializer
    widgets: {}

    rootWidget: null

    _loadingCount: 0

    _initEnd: false

    _widgetOrder: []

    _pushBindings: {}

    setRootWidget: (widget) ->
      @rootWidget = widget

    getTemplateCode: ->
      """
      <script src="vendor/requirejs/require.js"></script>
      <script>
        require(['./bundles/cord/core/browser-init'],
        function (browserInit, wi) {
          require(['cord!/cord/core/widgetInitializer'],
          function (wi) {
            $(function() {
              #{ @rootWidget.getInitCode() }
              wi.endInit();
            });
          });
        });
      </script>
      """

    endInit: ->
      @_initEnd = true

    ##
     #
     # @browser-only
     ##
    init: (widgetPath, ctx, namedChilds, childBindings, parentId) ->
      @_loadingCount++
      @_widgetOrder.push ctx.id

      for widgetId, bindingMap of childBindings
        @_pushBindings[widgetId] = {}
        for ctxName, paramName of bindingMap
          @_pushBindings[widgetId][ctxName] = paramName

      requireFunction ["cord-w!#{ widgetPath }"], (WidgetClass) =>
        widget = new WidgetClass ctx.id
        widget.loadContext ctx

        if @_pushBindings[ctx.id]?
          for ctxName, paramName of @_pushBindings[ctx.id]
            subscription = postal.subscribe
              topic: "widget.#{ parentId }.change.#{ ctxName }"
              callback: (data) ->
                params = {}
                params[paramName] = data.value
                console.log "(widgetInitializer) push binding event of parent (#{ parentId }) field #{ ctxName } for child widget #{ widget.constructor.name }::#{ widget.ctx.id }::#{ paramName }"
                widget.fireAction 'default', params
            widget.addSubscription subscription

        @widgets[ctx.id] =
          'widget': widget
          'namedChilds': namedChilds

        completeFunc = =>
          @_loadingCount--
          if @_loadingCount == 0 and @_initEnd
            @setupBindings()

        if parentId?
          retryCounter = 0
          timeoutFunc = =>
            if @widgets[parentId]?
              @widgets[parentId].widget.registerChild widget, @widgets[parentId].namedChilds[ctx.id] ? null
              completeFunc()
            else if retryCounter < 10
              console.log "widget load timeout activated", retryCounter
              setTimeout timeoutFunc, retryCounter++
            else
              throw "Try to use uninitialized parent widget with id = #{ parentId } - couldn't load parent widget within timeout!"
          timeoutFunc()
        else
          @rootWidget = widget
          completeFunc()


    setupBindings: ->
      @bind(id) for id in @_widgetOrder.reverse()

    bind: (widgetId) ->
      if @widgets[widgetId]?
        @widgets[widgetId].widget.initBehaviour()
      else
        throw "Try to use uninitialized widget with id = #{ widgetId }"

  new WidgetInitializer

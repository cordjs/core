define [
  'postal'
  'cord-helper'
], (postal, cordHelper) ->

  class WidgetInitializer
    widgets: {}

    rootWidget: null

    _loadingCount: 0

    _initEnd: false

    _widgetOrder: []

    _pushBindings: {}

    setRootWidget: (widget) ->
      @rootWidget = widget

    setCurrentBundle: (bundle) ->
      cordHelper.setCurrentBundle bundle, true

    getTemplateCode: ->
      """
      <script data-main="/bundles/cord/core/browserInit" src="/vendor/requirejs/require.js"></script>
      <script>
          function cordcorewidgetinitializerbrowser(wi) {
            wi.setCurrentBundle('#{ cordHelper.getCurrentBundle() }');
            #{ @rootWidget.getInitCode() }
            wi.endInit();
          };
      </script>
      """

    getTemplateCss: ->
      """
        #{ @rootWidget.getInitCss() }
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

      require ["cord-w!#{ widgetPath }"], (WidgetClass) =>
        widget = new WidgetClass ctx.id
        widget.setPath widgetPath
        widget.loadContext ctx

        # need to be in separate function to preserve context for the closure
        subscribePushBinding = (ctxName, paramName) ->
          postal.subscribe
            topic: "widget.#{ parentId }.change.#{ ctxName }"
            callback: (data, envelope) ->
              params = {}

              # param with name "params" is a special case and we should expand the value as key-value pairs
              # of widget's params
              if paramName == 'params'
                if _.isObject data.value
                  for subName, subValue of data.value
                    params[subName] = subValue
                else
                  # todo: warning?
              else
                params[paramName] = data.value

              console.log "(wi) push binding event of parent (#{ envelope.topic }) for child widget #{ widget.constructor.name }::#{ widget.ctx.id }::#{ paramName } -> #{ data.value }"
              widget.fireAction 'default', params
        ####

        if @_pushBindings[ctx.id]?
          for ctxName, paramName of @_pushBindings[ctx.id]
            console.log "#{ paramName }=\"^#{ ctxName }\" for #{ ctx.id }"
            subscription = subscribePushBinding ctxName, paramName
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

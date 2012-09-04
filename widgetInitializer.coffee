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

        if @_pushBindings[ctx.id]?
          for ctxName, paramName of @_pushBindings[ctx.id]
            console.log "#{ paramName }=\"^#{ ctxName }\" for #{ ctx.id }"
            @subscribePushBinding parentId, ctxName, widget, paramName

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


    #
    # Subscribes child widget to the parent widget's context variable change event
    #
    # @param String parentWidgetId id of the parent widget
    # @param String ctxName name of parent's context variable whose changes we are listening to
    # @param Widget childWidget subscribing child widget object
    # @param String paramName child widget's default action input param name which should be set to the context variable
    #                         value
    # @return postal subscription object
    #
    subscribePushBinding: (parentWidgetId, ctxName, childWidget, paramName) ->
      subscription = postal.subscribe
        topic: "widget.#{ parentWidgetId }.change.#{ ctxName }"
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

          console.log "(wi) push binding event of parent (#{ envelope.topic }) for child widget #{ childWidget.constructor.name }::#{ childWidget.ctx.id }::#{ paramName } -> #{ data.value }"
          childWidget.fireAction 'default', params
      childWidget.addSubscription subscription
      subscription


  new WidgetInitializer

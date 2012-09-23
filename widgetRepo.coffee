define [
  'postal'
  'cord!deferAggregator'
  'underscore'
], (postal, deferAggregator, _) ->

  class WidgetRepo
    widgets: {}

    rootWidget: null

    _loadingCount: 0

    _initEnd: false

    _widgetOrder: []

    _pushBindings: {}

    _currentExtendList: []
    _newExtendList: []

    createWidget: () ->
      ###
      Main widget factory.
      All widgets should be created through this call.

      @param String path canonical path of the widget
      @param (optional)String contextBundle calling context bundle to expand relative widget paths
      @param Callback(Widget) callback callback in which resulting widget will be passed as argument
      ###

      # normalizing arguments
      path = arguments[0]
      if _.isFunction arguments[1]
        callback = arguments[1]
        contextBundle = null
      else if _.isFunction arguments[2]
        callback = arguments[2]
        contextBundle = arguments[1]
      else
        throw "Callback should be passed to the widget factory!"

      bundleSpec = if contextBundle then "@#{ contextBundle }" else ''

      require ["cord-w!#{ path }#{ bundleSpec }"], (WidgetClass) =>
        widget = new WidgetClass
        widget.setRepo this
        callback widget

    setRootWidget: (widget) ->
      @rootWidget = widget

    getTemplateCode: ->
      """
      <script data-main="/bundles/cord/core/browserInit" src="/vendor/requirejs/require.js"></script>
      <script>
          function cordcorewidgetinitializerbrowser(wi) {
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
    init: (widgetPath, ctx, namedChilds, childBindings, isExtended, parentId) ->
      @_loadingCount++
      @_widgetOrder.push ctx.id

      for widgetId, bindingMap of childBindings
        @_pushBindings[widgetId] = {}
        for ctxName, paramName of bindingMap
          @_pushBindings[widgetId][ctxName] = paramName

      require ["cord-w!#{ widgetPath }"], (WidgetClass) =>
        widget = new WidgetClass ctx.id
        widget.loadContext ctx

        @_currentExtendList.push widget if isExtended

        if @_pushBindings[ctx.id]?
          for ctxName, paramName of @_pushBindings[ctx.id]
            #console.log "#{ paramName }=\"^#{ ctxName }\" for #{ ctx.id }"
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


    getById: (id) ->
      ###
      Returns widget with the given id if it is exists.
      Throws exception otherwise.
      @param String id widget id
      @return Widget
      ###

      if @widgets[widgetId]?
        @widgets[widgetId].widget
      else
        throw "Try to get uninitialized widget with id = #{ id }"



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
          deferAggregator.fireAction childWidget, 'default', params
      childWidget.addSubscription subscription
      subscription


    injectWidget: (widgetPath, action, params) ->
      extendWidget = @findAndCutMatchingExtendWidget widgetPath
      if extendWidget?
        extendWidget.fireAction action, params
        @setRootWidget extendWidget
      else
        @createWidget widgetPath, (widget) =>
          widget.injectAction action, params, =>
            @setRootWidget widget

    findAndCutMatchingExtendWidget: (widgetPath) ->
      result = null
      counter = 0
      for extendWidget in @_currentExtendList
        if widgetPath == extendWidget.getPath()
          found = true
          # removing all extend tree below found widget
          if counter > 0
            # unbind rest of widget tree to avoid cascade cleaning
            @_currentExtendList[counter - 1].unbindChild extendWidget
            @removeRootExtendWidget() while counter--
          # ... and prepending extend tree with the new widgets
          @_newExtendList.reverse()
          @_currentExtendList.unshift(wdt) for wdt in @_newExtendList
          @_newExtendList = []

          result = extendWidget
          break
        counter++
      result

    registerNewExtendWidget: (widget) ->
      @_newExtendList.push widget

    removeRootExtendWidget: ->
      widget = @_currentExtendList.shift()
      widget.clean()
      # todo: add some more removal (from dom placeholders)

    removeOldWidgets: ->
      # todo: smarter clean of widgetRepo
      @rootWidget.clean()
      @rootWidget = null
      @widgets = {}
      @_currentExtendList = @_newExtendList

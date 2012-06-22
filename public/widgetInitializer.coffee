`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [

], ->

  class WidgetInitializer
    widgets: {}

    rootWidget: null

    _loadingCount: 0

    _initEnd: false

    _widgetOrder: []

    setRootWidget: (widget) ->
      @rootWidget = widget

    getTemplateCode: ->
  #    items = ("new #{ widget.constructor.name }(#{ JSON.stringify(widget.ctx) });" for widget in @widgets)
      """
      <script>
        require(['./widgetInitializer'],
        function (wi) {
          $(function() {
            #{ @rootWidget.getInitCode()}
            wi.endInit();
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
    init: (widgetPath, ctx, namedChilds, parentId) ->
      console.log widgetPath

      @_loadingCount++
      @_widgetOrder.push ctx.id

      require ["./#{ widgetPath }"], (WidgetClass) =>
        widget = new WidgetClass ctx.id
        widget.loadContext ctx

        console.log ctx.id
        @widgets[ctx.id] =
          'widget': widget
          'namedChilds': namedChilds

        if parentId?
          if @widgets[parentId]?
            @widgets[parentId].widget.registerChild widget, @widgets[parentId].namedChilds[ctx.id] ? null
          else
            throw "Try to use uninitialized parent widget with id = #{ parentId }"

        @_loadingCount--
        console.log @_loadingCount
        if @_loadingCount == 0 and @_initEnd
          @setupBindings()


    setupBindings: ->
      console.log 'setupBindings'
      @bind(id) for id in @_widgetOrder.reverse()

    bind: (widgetId) ->
      console.log @, @widgets[widgetId], @widgets.widget1, widgetId
      if @widgets[widgetId]?
        @widgets[widgetId].widget.initBehaviour()
      else
        throw "Try to use uninitialized widget with id = #{ widgetId }"

  new WidgetInitializer

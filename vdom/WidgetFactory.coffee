define [
  'cord-w'
  'cord!utils/Future'
], (cordWidgetLoader, Promise) ->

  class WidgetFactory

    @inject: [
      'container'
      'vdomWidgetRepo'
      'widgetHierarchy'
    ]


    _widgetClassesCache: null


    constructor: ->
      @_widgetClassesCache = {}


    create: (type, props, slotNodes, parentWidget) ->
      ###
      Creates a new widget instance according to the given arguments
      @param {string} type - widget's class type path in cordjs format
      @param {Object.<string, *>} props - the props come from the parent widget
      @param {Array.<VNode>} slotNodes - slot contents to be inserted into the widget
      @param {Widget=} parentWidget - parent widget for the newly created widget
      @return {Promise.<Widget>}
      ###
      bundleSpec = if parentWidget then "@#{ parentWidget.constructor.bundle }" else ''

      @_getWidgetClass("#{type}#{bundleSpec}").then (WidgetClass) ->
        @container.injectServices(new WidgetClass(props: props, slotNodes: slotNodes))
      .then (widget) ->
        @vdomWidgetRepo.registerWidget(widget)
        @widgetHierarchy.registerChild(parentWidget, widget)  if parentWidget
        widget


    createByVWidget: (vWidget, parentWidget) ->
      ###
      Syntax-sugar factory - creates widget by the vDom node (vWidget) and parent widget
      @param {VWidget} vWidget
      @param {Widget} parentWidget - the parent widget
      @return {Promise.<Widget>}
      ###
      @create(vWidget.type, vWidget.properties, vWidget.slotNodes, parentWidget).then (widget) ->
        vWidget.widgetInstance = widget  # storing link to the actual widget instance optimizes vdom updating operations
        widget


    restore: (type, id, props, state, parentId) ->
      ###
      Restores previously created widget transferred from server to browser
      @param {string} type - widget's class type path in cordjs format (only absolute, no context uses)
      @param {string} id - the widget's id (generated on the server)
      @param {Object.<string, *>} props - the props come from the parent widget
      @param {Object.<string, *>} state - serialized widget's state
      @param {string=} parentId - parent widget id, used to restore hierarchy
      @return {Promise.<Widget>}
      ###
      @_getWidgetClass(type).then (WidgetClass) ->
        @container.injectServices(new WidgetClass(id: id, props: props, state: state))
      .then (widget) ->
        @vdomWidgetRepo.registerWidget(widget)
        @widgetHierarchy.registerChild(@vdomWidgetRepo.getById(parentId), widget)  if parentId
        widget


    _getWidgetClass: (widgetPath) ->
      ###
      Loads, caches and returns the widget class by cord-w style path.
      Helps to avoid calling requirejs multiple times and make things faster through caching the loaded class promise.
      @param {string} widgetPath - path without cord-w!
      @return {Promise.<Function>} widget class promise bound to `this` service (for optimization)
      ###
      canonicalPath = cordWidgetLoader.getFullInfo(widgetPath).canonicalPath
      if not @_widgetClassesCache[canonicalPath]
        @_widgetClassesCache[canonicalPath] = Promise.require('cord-w!'+widgetPath).bind(this) # bind is mandatory optimization
      @_widgetClassesCache[canonicalPath]

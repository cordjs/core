define [], ->

  class StructureTemplate

    constructor: (struct, rootWidget) ->
      @struct = struct
      @rootWidget = rootWidget

      @widgets = {}
      @widgets[struct.rootWidget] = rootWidget


    getWidget: (widgetRefId) ->
      if not @widgets[widgetRefId]?
        @widgets[widgetRefId] = @_initWidget widgetRefId
      @widgets[widgetRefId]

    _initWidget: (widgetRefId) ->
      info = @struct.widgets[widgetRefId]
      require [
        "cord-w!#{ info.fullClassName }"
      ], (WidgetClass) =>
        widget = new WidgetClass
        widget.injectPlaceholders

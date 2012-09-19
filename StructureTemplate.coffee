define [], ->

  class StructureTemplate

    constructor: (struct, rootWidget) ->
      @struct = struct
      @rootWidget = rootWidget

      @widgets = {}
      @widgets[struct.rootWidget] = rootWidget



    getWidget: (widgetRefId, callback) ->
      console.log 'getWidget', widgetRefId
      if @widgets[widgetRefId]?
        callback @widgets[widgetRefId]
      else
        @_initWidget widgetRefId, (widget) =>
          @widgets[widgetRefId] = widget
          callback widget


    _initWidget: (widgetRefId, callback) ->
      console.log '_initWidget', widgetRefId
      info = @struct.widgets[widgetRefId]
      require [
        "cord-w!#{ info.path }"
#        "cord-helper!#{ info.path }"
      ], (WidgetClass) =>
        widget = new WidgetClass
        widget.setPath info.path

        resolvedPlaceholders = {}

        # todo: make all this work in async (browser) environment
        for id, items of info.placeholders
          resolvedPlaceholders[id] = []
          for item in items
            if item.widget?
              @getWidget item.widget, (widget) ->
                resolvedPlaceholders[id].push
                  type: 'widget'
                  widget: widget
                  params: item.params
            else
              @getWidget item.inline, (widget) ->
                resolvedPlaceholders[id].push
                  type: 'inline'
                  widget: widget
                  template: item.template

        widget.injectPlaceholders resolvedPlaceholders
        callback widget

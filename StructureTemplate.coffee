define [], ->

  class StructureTemplate

    constructor: (struct, rootWidget) ->
      @struct = struct
      @rootWidget = rootWidget

      @widgets = {}
      @widgets[struct.rootWidget] = rootWidget



    getWidget: (widgetRefId, callback) ->
      if @widgets[widgetRefId]?
        callback @widgets[widgetRefId]
      else
        @_initWidget widgetRefId, (widget) =>
          @widgets[widgetRefId] = widget
          callback widget


    _initWidget: (widgetRefId, callback) ->
      info = @struct.widgets[widgetRefId]
      require ["cord-w!#{ info.path }"], (WidgetClass) =>
        widget = new WidgetClass

        waitCounter = 0
        waitCounterFinish = false

        resolvedPlaceholders = {}

        returnCallback = ->
          widget.injectPlaceholders resolvedPlaceholders
          callback widget

        for id, items of info.placeholders
          resolvedPlaceholders[id] = []
          for item in items
            waitCounter++
            if item.widget?
              @getWidget item.widget, (widget) =>
                @rootWidget.resolveParamRefs widget, item.params, (params) ->
                  resolvedPlaceholders[id].push
                    type: 'widget'
                    widget: widget
                    params: params
                  waitCounter--
                  if waitCounter == 0 and waitCounterFinish
                    returnCallback()
            else
              @getWidget item.inline, (widget) ->
                resolvedPlaceholders[id].push
                  type: 'inline'
                  widget: widget
                  template: item.template
                waitCounter--
                if waitCounter == 0 and waitCounterFinish
                  returnCallback()

        waitCounterFinish = true
        if waitCounter == 0
          returnCallback()

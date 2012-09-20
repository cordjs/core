define [], ->

  class StructureTemplate

    constructor: (struct, ownerWidget) ->
      @struct = struct
      @ownerWidget = ownerWidget

      @widgets = {}
      @widgets[struct.ownerWidget] = ownerWidget



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

        @injectPlaceholders widget, info.placeholders, ->
          callback widget


    injectPlaceholders: (targetWidget, placeholders, callback) ->
      waitCounter = 0
      waitCounterFinish = false

      resolvedPlaceholders = {}

      returnCallback = ->
        targetWidget.injectPlaceholders resolvedPlaceholders
        callback()

      for id, items of placeholders
        resolvedPlaceholders[id] = []
        for item in items
          waitCounter++
          if item.widget?
            @getWidget item.widget, (widget) =>
              @ownerWidget.resolveParamRefs widget, item.params, (params) ->
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


    assignWidget: (uid, newWidget) ->
      @widgets[uid] = newWidget

    reinjectPlaceholders: (extendInfo, callback) ->
      console.log "extendInfo = ", extendInfo, @struct
      @injectPlaceholders @widgets[extendInfo.widget], @struct.widgets[extendInfo.widget].placeholders, ->
        callback()


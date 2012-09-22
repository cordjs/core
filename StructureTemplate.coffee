define [
  'cord!widgetRepo'
], (widgetRepo) ->

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
      widgetRepo.createWidget info.path, (widget) =>
        @resolvePlaceholders widget, info.placeholders, (resolvedPlaceholders) ->
          widget.definePlaceholders resolvedPlaceholders
          callback widget


    resolvePlaceholders: (targetWidget, placeholders, callback) ->
      waitCounter = 0
      waitCounterFinish = false

      resolvedPlaceholders = {}

      returnCallback = ->
        callback resolvedPlaceholders

      for id, items of placeholders
        resolvedPlaceholders[id] = []
        for item in items
          waitCounter++
          if item.widget?
            @getWidget item.widget, (widget) =>
              @ownerWidget.registerChild widget
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

    replacePlaceholders: (extendInfo, callback) ->
      extendWidget = @widgets[extendInfo.widget]
      @resolvePlaceholders extendWidget, @struct.widgets[extendInfo.widget].placeholders, (resolvedPlaceholders) ->
        extendWidget.replacePlaceholders resolvedPlaceholders
        callback()


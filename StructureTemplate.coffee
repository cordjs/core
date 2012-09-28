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
      @ownerWidget.widgetRepo.createWidget info.path, (widget) =>
        @resolvePlaceholders widget, info.placeholders, (resolvedPlaceholders) ->
          widget.definePlaceholders resolvedPlaceholders
          callback widget

    getWidgetByName: (name, callback) ->
      if @struct.widgetsByName[name]?
        @getWidget @struct.widgetsByName[name], callback
      else
        throw "There is no widget with name '#{ name }' registered for template of #{ @ownerWidget.constructor.name }!"


    resolvePlaceholders: (targetWidget, newPlaceholders, callback) ->
      waitCounter = 0
      waitCounterFinish = false

      resolvedPlaceholders = {}

      returnCallback = ->
        callback resolvedPlaceholders

      for id, items of newPlaceholders
        do (id) =>
          resolvedPlaceholders[id] = []
          for item in items
            do (item) =>
              waitCounter++
              if item.widget?
                @getWidget item.widget, (widget) =>
                  @ownerWidget.registerChild widget
                  @ownerWidget.resolveParamRefs widget, item.params, (params) ->
                    resolvedPlaceholders[id].push
                      type: 'widget'
                      widget: widget.ctx.id
                      params: params
                    waitCounter--
                    if waitCounter == 0 and waitCounterFinish
                      returnCallback()
              else
                @getWidget item.inline, (widget) ->
                  resolvedPlaceholders[id].push
                    type: 'inline'
                    widget: widget.ctx.id
                    template: item.template
                    name: item.name
                    tag: item.tag
                    class: item.class
                  waitCounter--
                  if waitCounter == 0 and waitCounterFinish
                    returnCallback()

      waitCounterFinish = true
      if waitCounter == 0
        returnCallback()


    assignWidget: (uid, newWidget) ->
      @widgets[uid] = newWidget

    replacePlaceholders: (widgetUid, currentPlaceholders, callback) ->
      extendWidget = @widgets[widgetUid]
      currentPlaceholders ?= {}

      # search for appearence of the widget in current placeholder
      replaceHints = {}
      for id, items of @struct.widgets[widgetUid].placeholders
        replaceHints[id] = {}
        if currentPlaceholders[id]?
          if currentPlaceholders[id].length == items.length
            theSame = true
            i = 0
            for item in items
              if item.widget?
                curItem = currentPlaceholders[id][i]
                curWidget = @ownerWidget.widgetRepo.getById(curItem.widget)
                console.log "compare: #{ curItem.type } != 'widget' or #{ curWidget.getPath() } != #{ @struct.widgets[item.widget].path }"
                if curItem.type != 'widget' or curWidget.getPath() != @struct.widgets[item.widget].path
                  theSame = false
                  break
              else
                theSame = false
                break
              i++
          else
            theSame = false
        else
          theSame = false

        if theSame
          i = 0
          replaceHints[id].items = []
          replaceHints[id].replace = false
          for item in items
            refUid = item.widget
            curWidget = @ownerWidget.widgetRepo.getById(currentPlaceholders[id][i].widget)
            @assignWidget refUid, curWidget

            replaceHints[id].items.push refUid
        else
          replaceHints[id].replace = true

      @resolvePlaceholders extendWidget, @struct.widgets[widgetUid].placeholders, (resolvedPlaceholders) =>
        extendWidget.replacePlaceholders resolvedPlaceholders, this, replaceHints
        callback()


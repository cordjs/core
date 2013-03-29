define [
  'cord!isBrowser'
  'cord!utils/Future'
], (isBrowser, Future) ->

  class StructureTemplate

    constructor: (struct, ownerWidget) ->
      @struct = struct
      @ownerWidget = ownerWidget

      @widgets = {}
      @_reverseIndex = {}
      @assignWidget struct.ownerWidget, ownerWidget



    getWidget: (widgetRefId, callback) ->
#      console.log "#{ @ownerWidget.debug 'StructureTemplate' }::getWidget(#{ widgetRefId }) -> #{ if @widgets[widgetRefId]? then @widgets[widgetRefId].debug() else 'unexistent' }"
      if @widgets[widgetRefId]?
        callback @widgets[widgetRefId]
      else
        @_initWidget widgetRefId, (widget) =>
          @assignWidget widgetRefId, widget
          callback widget


    _initWidget: (widgetRefId, callback) ->
      info = @struct.widgets[widgetRefId]
      @ownerWidget.widgetRepo.createWidget info.path, @ownerWidget.getBundle(), (widget) =>
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

      for name, items of newPlaceholders
        do (name) =>
          resolvedPlaceholders[name] = []
          for item in items
            do (item) =>
              waitCounter++
              if item.widget?
                @getWidget item.widget, (widget) =>
                  @ownerWidget.registerChild widget, item.name

                  complete = false
                  timeoutPromise = null

                  @ownerWidget.resolveParamRefs widget, item.params, (params) =>
                    if not complete
                      complete = true
                      resolvedPlaceholders[name].push
                        type: 'widget'
                        widget: widget.ctx.id
                        params: params
                        class: item.class
                        timeout: item.timeout
                        timeoutTemplate: item.timeoutTemplate
                        timeoutTemplateOwner: if item.timeoutTemplate? then @ownerWidget else undefined
                      waitCounter--
                      if waitCounter == 0 and waitCounterFinish
                        returnCallback()
                    else
                      timeoutPromise.resolve(params)

                  if isBrowser and item.timeout? and item.timeout >= 0
                    setTimeout =>
                      if not complete
                        complete = true
                        timeoutPromise = new Future(1)
                        resolvedPlaceholders[name].push
                          type: 'timeouted-widget'
                          widget: widget.ctx.id
                          class: item.class
                          timeout: item.timeout
                          timeoutTemplate: item.timeoutTemplate
                          timeoutTemplateOwner: if item.timeoutTemplate? then @ownerWidget else undefined
                          timeoutPromise: timeoutPromise
                        waitCounter--
                        if waitCounter == 0 and waitCounterFinish
                          returnCallback()
                    , item.timeout

              else
                @getWidget item.inline, (widget) ->
                  resolvedPlaceholders[name].push
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


    assignWidget: (refUid, newWidget) ->
      @widgets[refUid] = newWidget
      @_reverseIndex[newWidget.ctx.id] = refUid

    unassignWidget: (widget) ->
#      console.log "StructureTemplate::unassignWidget(#{ widget.debug() })"
      if @_reverseIndex[widget.ctx.id]?
        delete @widgets[@_reverseIndex[widget.ctx.id]]
        delete @_reverseIndex[widget.ctx.id]
      else
        console.log "WARNING: trying to unassign unknown widget #{ widget.debug() }"


    replacePlaceholders: (widgetRefUid, currentPlaceholders, callback) ->
      extendWidget = @widgets[widgetRefUid]
      currentPlaceholders ?= {}

      # search for appearence of the widget in current placeholder
      replaceHints = {}
      for name, items of @struct.widgets[widgetRefUid].placeholders
        replaceHints[name] = {}
        if currentPlaceholders[name]?
          if currentPlaceholders[name].length == items.length
            theSame = true
            i = 0
            for item in items
              if item.widget?
                curItem = currentPlaceholders[name][i]
                curWidget = @ownerWidget.widgetRepo.getById(curItem.widget)
                #console.log "compare: #{ curItem.type } != 'widget' or #{ curWidget.getPath() } != #{ @struct.widgets[item.widget].path }"
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
          replaceHints[name].items = []
          replaceHints[name].replace = false
          for item in items
            refUid = item.widget
            curWidget = @ownerWidget.widgetRepo.getById(currentPlaceholders[name][i].widget)
            @assignWidget refUid, curWidget

            replaceHints[name].items.push refUid
        else
          replaceHints[name].replace = true

      @resolvePlaceholders extendWidget, @struct.widgets[widgetRefUid].placeholders, (resolvedPlaceholders) =>
        extendWidget.replacePlaceholders resolvedPlaceholders, this, replaceHints, ->
          callback()


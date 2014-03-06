define [
  'cord!isBrowser'
  'cord!utils/Future'
], (isBrowser, Future) ->

  class StructureTemplate

    @_empty: new this

    @emptyTemplate: -> @_empty


    constructor: (struct, ownerWidget) ->
      if struct?
        @struct = struct
        @ownerWidget = ownerWidget

        @widgets = {}
        @_reverseIndex = {}
        @assignWidget struct.ownerWidget, ownerWidget


    isEmpty: -> not @struct?


    isExtended: -> @struct? and @struct.extend?


    getWidget: (widgetRefId) ->
      ###
      Returns widget by it's structured reference id. If the widget has placeholders, they are being attached to it.
      Every widget initialized only once and cached (lazy).
      @param String widgetRefId
      @return Future[Widget]
      ###
      if @widgets[widgetRefId]?
        Future.resolved(@widgets[widgetRefId])
      else
        @_initWidget(widgetRefId).map (widget) =>
          @assignWidget widgetRefId, widget
          widget


    _initWidget: (widgetRefId) ->
      ###
      Actual widget initialization. Supports lazyness for the `getWidget` method
      @param String widgetRefId
      @return Future[Widget]
      ###
      info = @struct.widgets[widgetRefId]
      @ownerWidget.widgetRepo.createWidget(info.path, @ownerWidget.getBundle()).flatMap (widget) =>
        result = Future.single()
        @resolvePlaceholders widget, info.placeholders, (resolvedPlaceholders) ->
          widget.definePlaceholders resolvedPlaceholders
          result.resolve(widget)
        result


    getWidgetByName: (name) ->
      ###
      Initializes and returns widget by it's name property.
      @param String name
      @return Future[Widget]
      ###
      if @struct.widgetsByName[name]?
        @getWidget(@struct.widgetsByName[name])
      else
        Future.rejected(new Error(
          "There is no widget with name '#{ name }' registered for template of #{ @ownerWidget.constructor.__name }!"
        ))


    getWidgetInfoByName: (name) ->
      if @struct? and @struct.widgetsByName[name]? and @struct.widgets[@struct.widgetsByName[name]]?
        @struct.widgets[@struct.widgetsByName[name]]
      else
        null


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
                @getWidget(item.widget).done (widget) =>
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
                        timeoutPromise = new Future(1, 'StructureTemplate::resolvePlaceholders')
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

              else if item.inline?
                @getWidget(item.inline).done (widget) ->
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

              else if item.placeholder?
                @getWidget(item.placeholder).done (widget) ->
                  resolvedPlaceholders[name].push
                    type: 'placeholder'
                    widget: widget.ctx.id
                    name: item.name
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
      if @_reverseIndex[widget.ctx.id]?
        delete @widgets[@_reverseIndex[widget.ctx.id]]
        delete @_reverseIndex[widget.ctx.id]
      else
        # This is normal then widget template has not body blocks


    replacePlaceholders: (widgetRefUid, currentPlaceholders, transition, callback) ->
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
                #_console.log "compare: #{ curItem.type } != 'widget' or #{ curWidget.getPath() } != #{ @struct.widgets[item.widget].path }"
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

      @resolvePlaceholders extendWidget,
        @struct.widgets[widgetRefUid].placeholders,
        transition.if (resolvedPlaceholders) =>
          extendWidget.replacePlaceholders resolvedPlaceholders, this, replaceHints, transition, ->
            callback()


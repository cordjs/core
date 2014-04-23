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
      @ownerWidget.widgetRepo.createWidget(info.path, @ownerWidget.getBundle()).then (widget) =>
        @_resolvePlaceholders(info.placeholders).then (resolvedPlaceholders) ->
          widget.definePlaceholders(resolvedPlaceholders)
          widget


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


    assignWidget: (refUid, newWidget) ->
      @widgets[refUid] = newWidget
      @_reverseIndex[newWidget.ctx.id] = refUid


    unassignWidget: (widget) ->
      if @_reverseIndex[widget.ctx.id]?
        delete @widgets[@_reverseIndex[widget.ctx.id]]
        delete @_reverseIndex[widget.ctx.id]
      else
        # This is normal then widget template has not body blocks


    _resolvePlaceholders: (newPlaceholders) ->
      ###
      Converts abstract placeholders definition taken from the struct template to the resolved definition
       with references to the concrete created widgets.
      Result of this method is later used by the Widget::_renderPlaceholder() and Widget::replacePlaceholders()
       in order to actually (re-)render DOM structure.
      @param Map[String -> Array[Object]] newPlaceholders unresolved placeholders definition from the struct template
      @return Future[Map[String -> Array[Object]]] resolved placeholders definition for the widget
      ###
      resolvedPlaceholders = {}

      resultPromise = new Future("ST::resolvePlaceholders(#{@ownerWidget.debug()})")

      for name, items of newPlaceholders
        do (name) =>
          resolvedPlaceholders[name] = []
          for item in items
            do (item) =>
              resultPromise.fork()
              if item.widget?
                @getWidget(item.widget).failAloud().done (widget) =>
                  @ownerWidget.registerChild widget, item.name

                  complete = false
                  timeoutPromise = null

                  @ownerWidget.resolveParamRefs(widget, item.params).failAloud().done (params) =>
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
                      resultPromise.resolve()
                    else
                      timeoutPromise.resolve(params)

                  if isBrowser and item.timeout? and item.timeout >= 0
                    setTimeout =>
                      if not complete
                        complete = true
                        timeoutPromise = Future.single("ST::resolvePlaceholders:timeoutPromise(#{@ownerWidget.debug()})")
                        resolvedPlaceholders[name].push
                          type: 'timeouted-widget'
                          widget: widget.ctx.id
                          class: item.class
                          timeout: item.timeout
                          timeoutTemplate: item.timeoutTemplate
                          timeoutTemplateOwner: if item.timeoutTemplate? then @ownerWidget else undefined
                          timeoutPromise: timeoutPromise
                        resultPromise.resolve()
                    , item.timeout

              else if item.inline?
                @getWidget(item.inline).failAloud().done (widget) ->
                  resolvedPlaceholders[name].push
                    type: 'inline'
                    widget: widget.ctx.id
                    template: item.template
                    name: item.name
                    tag: item.tag
                    class: item.class
                  resultPromise.resolve()

              else if item.placeholder?
                @getWidget(item.placeholder).failAloud().done (widget) ->
                  resolvedPlaceholders[name].push
                    type: 'placeholder'
                    widget: widget.ctx.id
                    name: item.name
                    class: item.class
                  resultPromise.resolve()

      resultPromise.map -> resolvedPlaceholders


    replacePlaceholders: (widgetRefUid, currentPlaceholders, transition) ->
      ###
      Smartly replaces current placeholder contents of the given widget with the new contents
       during client-side page transition.
      New placeholder contents are taken from this structure template.
      @param String widgetRefUid id of the target widget in the structure template (usually from the #extend tag)
      @param Map[String -> Array[Object]] currentPlaceholders currently rendered placeholders definition of the widget
      @param PageTransition transition page transition helper
      @return Future
      ###
      newPlaceholders = @struct.widgets[widgetRefUid].placeholders

      replaceHints = @_diffPlaceholders(currentPlaceholders, newPlaceholders)

      @_resolvePlaceholders(newPlaceholders).then (resolvedPlaceholders) =>
        @widgets[widgetRefUid].replacePlaceholders(resolvedPlaceholders, this, replaceHints, transition)


    _diffPlaceholders: (current, replacing) ->
      ###
      Compares two placeholders definitions in order to detect if it's possible to not destroy current placeholders'
       contents but only push new widgets' params there.
      Only one none-destroy case is supported - when all of the placeholder's items are widgets (not inlines) and
       they are of the same type and the exactly same order. In that case existing widgets are assigned
       to the current struct template right here.
      @param Map[String -> Array[Object]] current resolved placeholders definition from the current rendered state
      @param Map[String -> Array[Object]] replacing new unresolved placeholders definition from the struct template
      @return Map[String -> Object] replace hints which are used later by the Widget::replacePlaceholders()
      ###
      current ?= {}

      # search for appearence of the widget in current placeholder
      replaceHints = {}
      for name, items of replacing
        replaceHints[name] = {}
        if current[name]?
          if current[name].length == items.length
            theSame = true
            i = 0
            for item in items
              if item.widget?
                curItem = current[name][i]
                curWidget = @ownerWidget.widgetRepo.getById(curItem.widget)
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
            curWidget = @ownerWidget.widgetRepo.getById(current[name][i].widget)
            @assignWidget refUid, curWidget

            replaceHints[name].items.push refUid
        else
          replaceHints[name].replace = true

      replaceHints

define [
  'underscore'
], (_) ->

  class WidgetCompiler

    structure: {}

    _extend: null
    _widgets: null
    _widgetsByName: null

    _extendPhaseFinished: false

    registerWidget: (widget, name) ->
      if not @_widgets[widget.ctx.id]?
        wdt =
          uid: widget.ctx.id
          path: widget.getPath()
          placeholders: {}
        if name?
          wdt.name = name
          @_widgetsByName[name] = wdt.uid
        @_widgets[widget.ctx.id] = wdt
      @_widgets[widget.ctx.id]


    reset: (ownerWidget) ->
      ###
      Resets compiler's state
      ###

      @_extendPhaseFinished = false
      @_extend = null
      @_widgets = {}
      @_widgetsByName = {}

      ownerInfo = @registerWidget ownerWidget

      @structure =
        ownerWidget: ownerInfo.uid
        extend: @_extend
        widgets: @_widgets
        widgetsByName: @_widgetsByName


    addExtendCall: (widget, params) ->
      if @_extendPhaseFinished
        throw "'#extend' appeared in wrong place (extending widget #{ widget.constructor.name })!"
      if @_extend?
        throw "Only one '#extend' is allowed per template (#{ widget.constructor.name })!"

      widgetRef = @registerWidget widget

      params = _.clone params
      delete params.type
      delete params.name

      @_extend =
        widget: widgetRef.uid
        params: params

      @structure.extend = @_extend


    addPlaceholderContent: (surroundingWidget, placeholderName, widget, params) ->
      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderName] ?= []
      swRef.placeholders[placeholderName].push
        widget: widgetRef.uid
        params: params


    addPlaceholderInline: (surroundingWidget, placeholderName, widget, templateName, name, tag, cls) ->
      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderName] ?= []
      swRef.placeholders[placeholderName].push
        inline: widgetRef.uid
        template: templateName
        name: name
        tag: tag
        class: cls


    getStructureCode: (compact = true) ->
      if @structure.widgets? and Object.keys(@structure.widgets).length > 1
        res = @structure
      else
        res = {}
      if compact
        JSON.stringify res
      else
        JSON.stringify res, null, 2

    printStructure: ->
      console.log @getStructureCode false


  new WidgetCompiler

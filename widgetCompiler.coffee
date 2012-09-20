define [
  'underscore'
], (_) ->

  class WidgetCompiler

    structure: {}

    _extend: null
    _widgets: {}

    _extendPhaseFinished: false

    registerWidget: (widget) ->
      if not @_widgets[widget.ctx.id]?
        wdt =
          uid: widget.ctx.id
          path: widget.getPath()
          placeholders: {}
        @_widgets[widget.ctx.id] = wdt
      @_widgets[widget.ctx.id]


    reset: (ownerWidget) ->
      ###
      Resets compiler's state
      ###
      console.log "COMPILER: reset"

      @_extendPhaseFinished = false
      @_extend = null
      @_widgets = {}

      ownerInfo = @registerWidget ownerWidget

      @structure =
        ownerWidget: ownerInfo.uid
        extend: @_extend
        widgets: @_widgets


    addExtendCall: (widget, params) ->
      console.log "COMPILER:addExtendCall #{ params.type }"

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


    addPlaceholderContent: (surroundingWidget, placeholderId, widget, params) ->
      console.log "COMPILER:addPlaceholderContent #{ placeholderId }, #{ widget.constructor.name }"

      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderId] ?= []
      swRef.placeholders[placeholderId].push
        widget: widgetRef.uid
        params: params


    addPlaceholderInline: (surroundingWidget, placeholderId, widget, templateName) ->
      console.log "COMPILER:addPlaceholderInline #{ placeholderId }, #{ widget.constructor.name }"

      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderId] ?= []
      swRef.placeholders[placeholderId].push
        inline: widgetRef.uid
        template: templateName


    getStructureCode: (compact = true) ->
      if compact
        JSON.stringify @structure
      else
        JSON.stringify @structure, null, 2

    printStructure: ->
      console.log @getStructureCode false


  new WidgetCompiler

define [
  'underscore'
], (_) ->

  class WidgetCompiler

    structure: {}

    _extendList: []
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


    reset: ->
      ###
      Resets compiler's state
      ###
      console.log "COMPILER: reset"

      @_extendPhaseFinished = false
      @_extendList = []
      @_widgets = {}
      @structure =
        extends: @_extendList
        widgets: @_widgets


    addExtendCall: (widget, params) ->
      console.log "COMPILER:addExtendCall #{ params.type }"

      if @_extendPhaseFinished
        throw "'#extend' appeared in wrong place (extending widget #{ widget.constructor.name })!"

      widgetRef = @registerWidget widget

      params = _.clone params
      delete params.type
      delete params.name

      @_extendList.push
        widget: widgetRef.uid
        params: params


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

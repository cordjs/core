define [
], () ->

  class WidgetCompiler

    tree: {}
    widgets: {}
    currentNode: null
    callStack: []

    registerWidget: (widget) ->
      if not @widgets[widget.ctx.id]?
        wdt =
          uid: widget.ctx.id
          path: widget.getPath()
          placeholders: {}
        @widgets[widget.ctx.id] = wdt
      @widgets[widget.ctx.id]


    setFirstWidget: (widget) ->
      @tree = {}
      widgetRef = @registerWidget widget
      @currentNode = @tree
      @tree.widget = widgetRef.uid


    addLayoutCall: (widget, params) ->
      console.log "COMPILER:addLayoutCall #{ params.type }"
      widgetRef = @registerWidget widget
      @currentNode.layout =
        widget: widgetRef.uid
      @callStack.unshift @currentNode
      @currentNode = @currentNode.layout
      delete params.type
      delete params.name
      @currentNode.params = params


    addPlaceholderContent: (surroundingWidget, placeholderId, widget, params) ->
      console.log "COMPILER:addPlaceholderContent #{ placeholderId }, #{ widget.constructor.name }"

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderId] ?= []
      swRef.placeholders[placeholderId].push
        widget: widgetRef.uid
        params: params


    addPlaceholderInline: (surroundingWidget, placeholderId, widget, templateName) ->
      console.log "COMPILER:addPlaceholderInline #{ placeholderId }, #{ widget.constructor.name }"

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderId] ?= []
      swRef.placeholders[placeholderId].push
        inline: widgetRef.uid
        template: templateName


    printTree: ->
      console.log JSON.stringify @tree, null, 2
      console.log JSON.stringify @widgets, null, 2


  new WidgetCompiler

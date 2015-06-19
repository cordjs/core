define [
  'cord!utils/Future'
  'cord!vdom/vpatch/patch'
  'cord!vdom/vtree/diff'
  'cord!vdom/vtree/vtree'
  'underscore'
], (Future, patch, diff, vtree, _) ->

  class Widget

    @inject: [
      'widgetFactory'
      'vdomWidgetRepo'
    ]


    getDir: ->
      @constructor.relativeDirPath


    getBundle: ->
      @constructor.bundle


    constructor: (props, slotNodes) ->
      @id = (if CORD_IS_BROWSER then 'w' else 'n') + _.uniqueId()
      @props = props or {}
      @updateSlots(slotNodes)


    updateProps: (newProps) ->
      @_restoreCurrentVtree().then =>
        changed = false
        for key, value of newProps
          # TODO replace with more sophisticated logic from Context
          if @props[key] != value
            changed = true
            @props[key] = value
        @render()  if changed
        return


    updateSlots: ->
      ###
      stub
      ###


    render: ->
      ###
      Updates the view via rendering vdom-template against current props and state,
       diffing result with the previous vtree and patching the DOM.
      @return {Promise.<undefined>} resolved when DOM is patched
      ###
      @_renderVtree().then (newVtree) =>
        patches = diff(@_vtree, newVtree)
        rootElement = document.getElementById(@id)
        patch(rootElement, patches, @vdomWidgetRepo)
        @_vtree = newVtree
        return
      .failAloud()


    renderDeepTree: ->
      ###
      Renders the widget with dereferencing child widgets (rendering them to the simple VNodes) deeply.
      @return {Promise.<VNode>}
      ###
      @_renderVtree().then (vnode) =>
        @_recDereferenceTree(vnode)


    _recDereferenceTree: (vnode) ->
      ###
      Recursively scans the given VNode and replaces VWidget occurences with the rendered widget VNode
      @param {VNode} vnode
      @return {Promise.<VNode>}
      ###
      if vtree.isWidget(vnode)
        @_renderDeepVWidget(vnode)
      else if vtree.isVNode(vnode)
        promises = (@_recDereferenceTree(child) for child in vnode.children)
        Future.all(promises).then (dereferencedChildren) ->
          vnode.children = dereferencedChildren
          vnode
      else
        Future.resolved(vnode)


    _renderDeepVWidget: (vwidget) ->
      ###
      Renders (dereference) VWidget node and recursively dereference it's VTree.
      @param {VWidget} vwidget
      @return {Promise.<VNode>}
      ###
      @widgetFactory.create(vwidget.type, vwidget.props, vwidget.slotNodes, @getBundle()).then (widget) ->
        widget.renderDeepTree()


    _renderVtree: ->
      ###
      Renders the widget's template to the virtual DOM tree, using current state and props
      @return {Promise.<VNode>}
      ###
      vdomTmplFile = "bundles/#{ @getDir() }/#{ @constructor.dirName }.vdom"

      calc = {}
      @onRender?(calc)

      Future.require(vdomTmplFile).then (renderFn) =>
        vnode = renderFn(@props, @state, calc)
        vnode.properties.id = @id
        vnode


    _restoreCurrentVtree: ->
      ###
      @return {Promise.<VTree>}
      @todo protect from calling twice concurrently
      ###
      if not @_vtree
        @_renderVtree().then (vtree) =>
          @_vtree = vtree
      else
        Future.resolved(@_vtree)

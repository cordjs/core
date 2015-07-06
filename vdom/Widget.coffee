define [
  'cord!utils/Future'
  'cord!vdom/vtree/diff'
  'cord!vdom/vtree/vtree'
  'cord!vdom/vtree/utils'
  'underscore'
], (Future, diff, vtree, vtreeUtils, _) ->

  class Widget

    @inject: [
      'domPatcher'
      'vdomWidgetRepo'
      'widgetFactory'
      'widgetHierarchy'
    ]


    constructor: (params = {}) ->
      @id = params.id or ((if CORD_IS_BROWSER then 'b' else 'n') + _.uniqueId())
      @props = params.props or {}
      @state = params.state or {}


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


    render: ->
      ###
      Updates the view via rendering vdom-template against current props and state,
       diffing result with the previous vtree and patching the DOM.
      @return {Promise.<undefined>} resolved when DOM is patched
      ###
      @_renderVtree().then (newVtree) =>
        patches = diff(@_vtree, newVtree)
        rootElement = document.getElementById(@id)
        @domPatcher.patch(rootElement, patches, this).then =>
          @_vtree = newVtree
          return
      .failAloud()


    renderDeepTree: ->
      ###
      Renders the widget with dereferencing child widgets (rendering them to the simple VNodes) deeply.
      @return {Promise.<VNode>}
      ###
      @_renderVtree().then (vnode) =>
        @_vtree = vnode
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
        vnode = vtreeUtils.clone(vnode) # cloning is necessary to avoid dereferencing currently stored @_vtree
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
      @widgetFactory.createByVWidget(vwidget, this).then (widget) ->
        widget.renderDeepTree()


    _renderVtree: ->
      ###
      Renders the widget's template to the virtual DOM tree, using current state and props
      @return {Promise.<VNode>}
      ###
      calc = {}
      @onRender?(calc)

      @constructor.getTemplate().then (renderFn) =>
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


    getInitCode: (parentId) ->
      parentStr = if parentId? then ",'#{ parentId }'" else ''

      # todo: maybe add refs (aka childByName)

      # todo: add model bindings serialization

      # filter bad unicode characters before sending data to browser
      propsStr = unescape(encodeURIComponent(JSON.stringify(@props))).replace(/<\/script>/g, '<\\/script>')
      stateStr = unescape(encodeURIComponent(JSON.stringify(@state))).replace(/<\/script>/g, '<\\/script>')

      # indentation is mandatory to beautify page source formatting
      """
            wi.vdomInit('#{@id}','#{@constructor.path}',#{propsStr},#{stateStr}#{parentStr});
      #{ (widget.getInitCode(@id) for widget in @widgetHierarchy.getChildren(this)).join('') }
      """


    @getTemplate: ->
      ###
      Loads, caches and returns widget's vDom template function.
      Avoids redundant using of requirejs which causes slow setTimeout calls for async.
      @static
      @return {Promise.<function>}
      ###
      if not @_cachedTemplatePromise
        vdomTmplFile = "bundles/#{ @relativeDirPath }/#{ @dirName }.vdom"
        @_cachedTemplatePromise = Future.require(vdomTmplFile)
      @_cachedTemplatePromise

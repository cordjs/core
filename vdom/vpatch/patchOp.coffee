define [
  './applyProperties'
  './createElement'
  './updateAlienWidget'
  '../vtree/vtree'
  '../vtree/VPatch'
  'cord!utils/Future'
], (applyProperties, render, updateAlienWidget, vtree, VPatch, Promise) ->

  applyPatch = (vpatch, patchScript, renderOptions) ->
    ###
    Fills the given patch-script with DOM manipulation commands according to the given VPatch structure from vDom diff.
    @param {VPatch} vpatch - single vpatch from the vdom diff algorithm
    @param {PatchScript} patchScript - the patch-script to which DOM update commands should be recorded
    @param {Object} renderOptions - additional information need to be provided for some of patch commands
    @return {PatchScript|Promise.<PatchScript>}
    ###
    type = vpatch.type
    vNode = vpatch.vNode
    patch = vpatch.patch
    switch type
      when VPatch.REMOVE
        removeNode patchScript, vNode
      when VPatch.INSERT
        insertNode patchScript, patch, renderOptions
      when VPatch.VTEXT
        stringPatch patchScript, vNode, patch, renderOptions
      when VPatch.ALIEN_WIDGET
        patchScript.alienWidgetPatch(vNode, patch, renderOptions)
      when VPatch.VNODE
        vNodePatch patchScript, vNode, patch, renderOptions
      when VPatch.ORDER
        patchScript.reorderChildren(patch)
      when VPatch.PROPS
        patchScript.applyProperties(patch, vNode.properties)
      when VPatch.WIDGET_PROPS
        if vNode.widgetInstance
          vNode.widgetInstance.updateProps(patch)
          patchScript
        else
          # if there is no widgetInstance link cached than we need to access DOM to find out the widget ID
          patchScript.updateWidgetProps(patch, renderOptions.widgetRepo)
      when VPatch.WIDGET
        vWidgetPatch patchScript, vNode, patch, renderOptions
#      when VPatch.THUNK
#        replaceRoot(domNode, renderOptions.patch(domNode, patch, renderOptions))
      else
        console.warn 'Unsupported patch command!', type
        patchScript


  vWidgetPatch = (patchScript, leftVNode, vWidget, renderOptions) ->
    ###
    Generates patch-script commands for the case when some vDom node is replaced with a new widget.
    ###
    renderOptions.widgetFactory.createByVWidget(vWidget, renderOptions.widget).then (widget) ->
      widget.renderDeepTree()
    .then (vtree) ->
      newNode = render(vtree, renderOptions)
      patchScript.replaceNode(newNode)
      patchScript.destroyAlienWidget(leftVNode)


  removeNode = (patchScript, vNode) ->
    ###
    Generates patch-script commands for the case when any node is removed.
    ###
    patchScript.removeNode()
    patchScript.destroyAlienWidget(vNode)


  insertNode = (patchScript, vNode, renderOptions) ->
    ###
    Generates patch-script commands for the case when new node (or widget) is appended to the tree.
    ###
    newNodePromise =
      if vtree.isWidget(vNode)
        # plain node is replaced with widget
        renderOptions.widgetFactory.createByVWidget(vNode, renderOptions.widget).then (widget) ->
          widget.renderDeepTree()
      else
        Promise.resolved(vNode)
    newNodePromise.then (vtree) ->
      newNode = render(vtree, renderOptions)
      patchScript.appendChild(newNode)


  stringPatch = (patchScript, leftVNode, vText, renderOptions) ->
    ###
    Generates patch-script commands for the case when text node is updated or replaces another node.
    ###
    patchScript.stringPatch(vText, renderOptions)
    patchScript.destroyAlienWidget(leftVNode)


  vNodePatch = (patchScript, leftVNode, vNode, renderOptions) ->
    ###
    Generates patch-script commands for the case when a new node replaces another node
    ###
    newNode = render(vNode, renderOptions)
    patchScript.replaceNode(newNode)
    patchScript.destroyAlienWidget(leftVNode)


#  replaceRoot = (oldRoot, newRoot) ->
#    if oldRoot and newRoot and oldRoot != newRoot and oldRoot.parentNode
#      oldRoot.parentNode.replaceChild newRoot, oldRoot
#    newRoot


  applyPatch

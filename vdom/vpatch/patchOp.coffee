define [
  './applyProperties'
  './createElement'
  './updateAlienWidget'
  '../vtree/vtree'
  '../vtree/VPatch'
], (applyProperties, render, updateAlienWidget, vtree, VPatch) ->

  applyPatch = (vpatch, domNode, renderOptions) ->
    type = vpatch.type
    vNode = vpatch.vNode
    patch = vpatch.patch
    switch type
      when VPatch.REMOVE
        removeNode domNode, vNode
      when VPatch.INSERT
        insertNode domNode, patch, renderOptions
      when VPatch.VTEXT
        stringPatch domNode, vNode, patch, renderOptions
      when VPatch.ALIEN_WIDGET
        alienWidgetPatch domNode, vNode, patch, renderOptions
      when VPatch.VNODE
        vNodePatch domNode, vNode, patch, renderOptions
      when VPatch.ORDER
        reorderChildren domNode, patch
        domNode
      when VPatch.PROPS
        applyProperties domNode, patch, vNode.properties
        domNode
      when VPatch.THUNK
        replaceRoot(domNode, renderOptions.patch(domNode, patch, renderOptions))
      else
        domNode


  removeNode = (domNode, vNode) ->
    parentNode = domNode.parentNode
    parentNode.removeChild(domNode)  if parentNode
    destroyAlienWidget domNode, vNode
    null


  insertNode = (parentNode, vNode, renderOptions) ->
    newNode = render(vNode, renderOptions)
    parentNode.appendChild(newNode)  if parentNode
    parentNode


  stringPatch = (domNode, leftVNode, vText, renderOptions) ->
    if domNode.nodeType == 3
      domNode.replaceData(0, domNode.length, vText.text)
      newNode = domNode
    else
      parentNode = domNode.parentNode
      newNode = render(vText, renderOptions)
      parentNode.replaceChild(newNode, domNode)  if parentNode
    destroyAlienWidget domNode, leftVNode
    newNode


  alienWidgetPatch = (domNode, leftVNode, widget, renderOptions) ->
    return widget.update(leftVNode, domNode) or domNode  if updateAlienWidget(leftVNode, widget)
    parentNode = domNode.parentNode
    newWidget = render(widget, renderOptions)
    parentNode.replaceChild(newWidget, domNode)  if parentNode
    destroyAlienWidget domNode, leftVNode
    newWidget


  vNodePatch = (domNode, leftVNode, vNode, renderOptions) ->
    parentNode = domNode.parentNode
    newNode = render(vNode, renderOptions)
    parentNode.replaceChild(newNode, domNode)  if parentNode
    destroyAlienWidget domNode, leftVNode
    newNode


  destroyAlienWidget = (domNode, w) ->
    w.destroy(domNode)  if typeof w.destroy == 'function' and vtree.isAlienWidget(w)
    return


  reorderChildren = (domNode, bIndex) ->
    children = []
    childNodes = domNode.childNodes
    reverseIndex = bIndex.reverse

    children.push(child) for child in childNodes

    insertOffset = 0
    move = undefined
    insertNode = undefined

    len = childNodes.length
    i = 0
    while i < len
      move = bIndex[i]
      if move != undefined and move != i
        # the element currently at this index will be moved later so increase the insert offset
        insertOffset++  if reverseIndex[i] > i

        node = children[move]
        insertNode = childNodes[i + insertOffset] or null
        domNode.insertBefore(node, insertNode)  if node != insertNode

        # the moved element came from the front of the array so reduce the insert offset
        insertOffset--  if move < i

      # element at this index == scheduled to be removed so increase insert offset
      insertOffset++  if i of bIndex.removes

      i++

    return


  replaceRoot = (oldRoot, newRoot) ->
    if oldRoot and newRoot and oldRoot != newRoot and oldRoot.parentNode
      console.log oldRoot
      oldRoot.parentNode.replaceChild newRoot, oldRoot
    newRoot


  applyPatch

define [
  './applyProperties'
  '../vtree/handleThunk'
  '../vtree/vtree'
], (applyProperties, handleThunk, vtree) ->

  createElement = (vnode, opts) ->
    doc = (if opts then opts.document or document else document)
    warn = (if opts then opts.warn else null)

    vnode = handleThunk(vnode).a

    if vtree.isWidget(vnode)
      return vnode.init()
    else if vtree.isVText(vnode)
      return doc.createTextNode(vnode.text)
    else if not vtree.isVNode(vnode)
      warn 'Item is not a valid virtual dom node', vnode  if warn
      return null

    node =
      if vnode.namespace == null
        doc.createElement(vnode.tagName)
      else
        doc.createElementNS(vnode.namespace, vnode.tagName)

    props = vnode.properties
    applyProperties node, props

    for child in vnode.children
      childNode = createElement(child, opts)
      node.appendChild(childNode)  if childNode

    node


  createElement

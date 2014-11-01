define [
  '../vtree/vtree'
  '../vtree/VNode'
  '../vtree/VText'
  './parseTag'
  './hooks/DataSetHook'
  './hooks/EvHook'
  './hooks/SoftSetHook'
  'underscore'
], (vtree, VNode, VText, parseTag, DataSetHook, EvHook, SoftSetHook, _) ->

  h = (tagName, properties, children) ->
    childNodes = []
    tag = undefined
    props = undefined
    key = undefined
    namespace = undefined
    if not children and isChildren(properties)
      children = properties
      props = {}
    props = props or properties or {}
    tag = parseTag(tagName, props)

    # support keys
    if 'key' of props
      key = props.key
      props.key = undefined

    # support namespace
    if 'namespace' of props
      namespace = props.namespace
      props.namespace = undefined

    # fix cursor bug
    if tag == 'input' and ('value' of props) and props.value != undefined and not vtree.isHook(props.value)
      props.value = new SoftSetHook(props.value)

    for propName, value of props
      continue  if vtree.isHook(value)

      # add data-foo support
      props[propName] = new DataSetHook(value)  if propName.substr(0, 5) == 'data-'

      # add ev-foo support
      props[propName] = new EvHook(value)  if propName.substr(0, 3) == 'ev-'

    addChild(children, childNodes, tag, props)  if children?
    node = new VNode(tag, props, childNodes, key, namespace)
    node


  addChild = (c, childNodes, tag, props) ->
    if typeof c == 'string'
      childNodes.push(new VText(c))
    else if isChild(c)
      childNodes.push(c)
    else if _.isArray(c)
      addChild(child, childNodes, tag, props)  for child in c
    else if not c?
      return
    else
#      throw UnexpectedVirtualElement(
      throw
        foreignObjectStr: JSON.stringify(c)
        foreignObject: c
        parentVnodeStr: JSON.stringify
          tagName: tag
          properties: props
        parentVnode:
          tagName: tag
          properties: props
    return


  isChild = (x) ->
    vtree.isVNode(x) or vtree.isVText(x) or vtree.isWidget(x) or vtree.isThunk(x)


  isChildren = (x) ->
    typeof x == 'string' or _.isArray(x) or isChild(x)


#  UnexpectedVirtualElement = TypedError
#    type: "virtual-hyperscript.unexpected.virtual-element"
#    message: "Unexpected virtual child passed to h().\n" +
#      "Expected a VNode / Vthunk / VWidget / string but:\n" +
#      "got a {foreignObjectStr}.\n" +
#      "The parent vnode is {parentVnodeStr}.\n" +
#      "Suggested fix: change your `h(..., [ ... ])` callsite."
#    foreignObjectStr: null
#    parentVnodeStr: null
#    foreignObject: null
#    parentVnode: null


  h

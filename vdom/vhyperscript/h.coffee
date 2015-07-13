define [
  '../vtree/vtree'
  '../vtree/VNode'
  '../vtree/VText'
  '../vtree/VWidget'
  './parseTag'
  './hooks/DataSetHook'
  './hooks/EvHook'
  './hooks/SoftSetHook'
  'cord!utils/Future'
  'underscore'
], (vtree, VNode, VText, VWidget, parseTag, DataSetHook, EvHook, SoftSetHook, Promise, _) ->

  noProps = {}

  h = (tagName, properties, children) ->
    props = undefined
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

    propPromises = null
    for propName, value of props
      if value instanceof Promise
        do (propName) ->
          valuePromise = value.then (resolved) ->
            # code supporting promise-values of props is somewhat duplicate of the code for sync values, but it's ok
            props[propName] =
              if vtree.isHook(resolved)
                resolved
              else if propName.substr(0, 5) == 'data-'
                # add data-foo support
                new DataSetHook(resolved)
              else if propName.substr(0, 3) == 'ev-'
                # add ev-foo support
                new EvHook(resolved)
              else
                resolved
            return
          propPromises ?= []
          propPromises.push(valuePromise)
      else if not vtree.isHook(value)
        if propName.substr(0, 5) == 'data-'
          # add data-foo support
          props[propName] = new DataSetHook(resolved)
        else if propName.substr(0, 3) == 'ev-'
          # add ev-foo support
          props[propName] = new EvHook(resolved)

    childNodes = []
    addChild(children, childNodes, tag, props)  if children?

    if propPromises
      if containsPromise(childNodes)
        Promise.all [
          Promise.all(childNodes)
          Promise.all(propPromises)
        ]
        .spread (resolvedNodes) ->
          new VNode(tag, props, resolvedNodes, key, namespace)
      else
        Promise.all(propPromises).then ->
          new VNode(tag, props, childNodes, key, namespace)
    else if containsPromise(childNodes)
      Promise.all(childNodes).then (resolvedNodes) ->
        new VNode(tag, props, resolvedNodes, key, namespace)
    else
      new VNode(tag, props, childNodes, key, namespace)


  h.w = (type, props, slotContents) ->
    if not slotContents and isChildren(props)
      slotContents = props
      props = noProps
    props or= noProps

    # support keys
    if 'key' of props
      key = props.key
      props.key = undefined

    if slotContents?
      slotNodes = []
      addChild(slotContents, slotNodes, type, props)
    new VWidget(type, props, slotNodes, key)


  h.v = (args...) ->
    ###
    Utility function that concats passed arguments with consideration of some arguments may be promises.
    If any argument is a promise, then whole concatted result is wrapped into promise.
    @param {...string|Promise.<string>} args
    @return {string|Promise.<string>}
    ###
    if containsPromise(args)
      Promise.all(args).then(concatStringifiedArgs)
    else
      concatStringifiedArgs(args)


  concatStringifiedArgs = (args) ->
    ###
    Converts all items of the given array to string and concats them together.
    @param {Array} args
    @return {string}
    ###
    result = ''
    result += String(part)  for part in args
    result


  containsPromise = (arr) ->
    ###
    Returns true if the given array contains a promise item
    @param {Array} arr
    @return {boolean}
    ###
    for arg in arr
      return true  if arg instanceof Promise
    return false


  addChild = (c, childNodes, tag, props) ->
    if typeof c == 'string'
      childNodes.push(new VText(c))
    else if isChild(c)
      childNodes.push(c)
    else if _.isArray(c)
      addChild(child, childNodes, tag, props)  for child in c
    else if c instanceof Promise
      childNodes.push(
        c.then (res) ->
          if typeof res == 'string'
            new VText(res)
          else
            res
      )
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
    vtree.isVNode(x) or vtree.isVText(x) or vtree.isWidget(x) or vtree.isAlienWidget(x) or vtree.isThunk(x)


  isChildren = (x) ->
    typeof x == 'string' or _.isArray(x) or isChild(x) or x instanceof Promise


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

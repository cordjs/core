define [
  '../vtree/vtree'
  'underscore'
], (vtree, _) ->

  applyProperties = (node, props, previous) ->
    for propName, propValue of props
      if propValue == undefined
        removeProperty node, props, previous, propName
      else if vtree.isHook(propValue)
        propValue.hook(node, propName, (if previous then previous[propName] else undefined))
      else
        if _.isObject(propValue)
          patchObject node, props, previous, propName, propValue
        else if propValue != undefined
          node[propName] = propValue
    return


  removeProperty = (node, props, previous, propName) ->
    if previous
      previousValue = previous[propName]

      if not vtree.isHook(previousValue)
        if propName == 'attributes'
          for attrName of previousValue
            node.removeAttribute(attrName)
        else if propName == 'style'
          for i of previousValue
            node.style[i] = ''
        else if typeof previousValue == 'string'
          node[propName] = ''
        else
          node[propName] = null
    return


  patchObject = (node, props, previous, propName, propValue) ->
    previousValue = (if previous then previous[propName] else undefined)

    # Set attributes
    if propName == 'attributes'
      for attrName, attrValue of propValue
        if attrValue == undefined
          node.removeAttribute attrName
        else
          node.setAttribute attrName, attrValue

      return

    if previousValue and _.isObject(previousValue) and getPrototype(previousValue) != getPrototype(propValue)
      node[propName] = propValue
      return

    node[propName] = {}  if not _.isObject(node[propName])

    replacer = (if propName == 'style' then '' else undefined)

    for k, value of propValue
      node[propName][k] = (if (value == undefined) then replacer else value)

    return


  getPrototype = (value) ->
    if Object.getPrototypeOf
      Object.getPrototypeOf(value)
    else if value.__proto__
      value.__proto__
    else if value.constructor
      value.constructor::


  applyProperties

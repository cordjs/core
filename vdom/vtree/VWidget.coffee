define [
  './vtree'
], (vtree) ->

  noProperties = {}
  noChildren = []


  VWidget = (type, props, slotNodes, key) ->
    @type = type
    @slotNodes = slotNodes || noChildren
    @key = if key? then String(key) else undefined

    count = (slotNodes and slotNodes.length) or 0
    descendants = 0
    hasAlienWidgets = false
    descendantHooks = false
    hooks = null

    if props
      @properties = props
      for propName in props
        if props.hasOwnProperty(propName)
          property = props[propName]
          if vtree.isVHook(property)
            hooks ||= {}
            hooks[propName] = property
    else
      @properties = noProperties

    if count
      for child in slotNodes
        if vtree.isVNode(child)
          descendants += child.count or 0
          hasAlienWidgets = true if not hasAlienWidgets and child.hasAlienWidgets

          if not descendantHooks and (child.hooks or child.descendantHooks)
            descendantHooks = true

        else if not hasAlienWidgets and vtree.isAlienWidget(child)
          hasAlienWidgets = true if typeof child.destroy == 'function'

    @count = count + descendants
    @hasAlienWidgets = hasAlienWidgets
    @hooks = hooks
    @descendantHooks = descendantHooks


  VWidget.type = 'VWidget'

  VWidget

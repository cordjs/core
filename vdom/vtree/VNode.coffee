define [
  './vtree'
], (vtree) ->

  noProperties = {}
  noChildren = []


  VNode = (tagName, properties, children, key, namespace) ->
    @tagName = tagName
    @properties = properties || noProperties
    @children = children || noChildren
    @key = if key? then String(key) else undefined
    @namespace = if typeof namespace == 'string' then namespace else null

    count = (children and children.length) or 0
    descendants = 0
    hasAlienWidgets = false
    descendantHooks = false
    hooks = null

    for propName in properties
      if properties.hasOwnProperty(propName)
        property = properties[propName]
        if vtree.isVHook(property)
          hooks ||= {}
          hooks[propName] = property

    if count
      for child in children
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


  VNode.type = 'VNode'

  VNode

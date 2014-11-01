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
    hasWidgets = false
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
          descendants += child.count || 0
          hasWidgets = true if not hasWidgets and child.hasWidgets

          if not descendantHooks and (child.hooks or child.descendantHooks)
            descendantHooks = true

        else if not hasWidgets and vtree.isWidget(child)
          hasWidgets = true if typeof child.destroy == 'function'

    @count = count + descendants
    @hasWidgets = hasWidgets
    @hooks = hooks
    @descendantHooks = descendantHooks


  VNode.type = 'VNode'

  VNode

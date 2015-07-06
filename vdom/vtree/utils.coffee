define [
  './VNode'
  './VText'
  './VWidget'
], (VNode, VText, VWidget) ->

  clone: (x) ->
    ###
    Creates a shallow-copy of the given vtree entity without calling a constructor.
    @param {VNode|VText|VWidget} x
    @return {VNode|VText|VWidget}
    ###
    result = undefined
    switch x.constructor.type
      when 'VNode'
        result =
          tagName: x.tagName
          properties: x.properties
          children: x.children
          key: x.key
          namespace: x.namespace
          count: x.count
          hasAlienWidgets: x.hasAlienWidgets
          hooks: x.hooks
          descendantHooks: x.descendantHooks
        result.constructor = VNode

      when 'VText'
        result = text: x.text
        result.constructor = VText

      when 'VWidget'
        result =
          type: x.type
          slotNodes: x.slotNodes
          key: x.key
          count: x.count
          hasAlienWidgets: x.hasAlienWidgets
          hooks: x.hooks
          descendantHooks: x.descendantHooks
          widgetInstance: x.widgetInstance
        result.constructor = VWidget
    result

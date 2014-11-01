define ->

  AttributeHook = (value) ->
    @value = value


  AttributeHook::hook = (node, prop, prev) ->
    node.setAttributeNS(null, prop, this.value)  if not (prev and prev.value == @value)


  AttributeHook

define ->

  SoftSetHook = (value) ->
    @value = value


  SoftSetHook::hook = (node, propertyName) ->
    node[propertyName] = @value  if node[propertyName] != @value


  SoftSetHook

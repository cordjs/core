define ->

  EvHook = (value) ->
    @value = value


  EvHook::hook = (node, propertyName) ->
    ds = DataSet(node)
    propName = propertyName.substr(3)
    ds[propName] = @value


  EvHook

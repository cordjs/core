define ->

  DataSetHook = (value) ->
    @value = value


  DataSetHook::hook = (node, propertyName) ->
    ds = DataSet(node)
    propName = propertyName.substr(5)
    ds[propName] = @value


  DataSetHook

define [], ->

  load: (name, req, load, config) ->
    if name.indexOf('//') != -1
      throw "cord! extension can not be used with shorted path notation (using //): [#{ name }]!"
    if name.substr(0, 1) != '/'
      nameParts = name.split '@'
      if nameParts.length == 2
        name = nameParts[0]
        bundle = nameParts[1]
      else
        bundle = '/cord/core'
      name = "#{ bundle }/#{ name }"
    else if name.indexOf('@') != -1
      throw "Bundle spec for fully-qualified name is not supported!"

    req [config.paths.bundles + name], (module) ->
      load module

define [
  'dustjs-linkedin'
], (dust) ->

  getFullInfo: (name) ->
    # todo: remove code duplication with cord-w
    bundleSpec = null
    nameParts = name.split '@'
    throw "Not more than one @ is allowed in the widget name specification: #{ name }!" if nameParts.length > 2
    if nameParts.length == 2
      bundleSpec = nameParts[1]
      throw "Bundle specification should start with /: #{ name }" if bundleSpec.indexOf('/') != 0
      if bundleSpec.substr(-1) == '/'
        console.warn "WARNING: trailing slash in bundle specification is deprecated: #{ name }! Cutting..."
        bundleSpec = bundleSpec.substr(0, bundleSpec.length - 1)
    name = nameParts[0]

    if name.indexOf('/') == -1
      bundleSpec = '/cord/core' if not bundleSpec?
      relativePath = name
    else
      nameParts = name.split '//'
      throw "Not more than one // is allowed in widget name specification: #{ name }!" if nameParts.length > 2
      if nameParts.length == 2
        ns = nameParts[0]
        relativePath = nameParts[1]

        if ns.indexOf('/') == 0
          bundleSpec = ns
        else
          throw "Unknown bundle for widget: #{ name }" if not bundleSpec?
          if ns != ''
            bundleParts = bundleSpec.split '/'
            nsParts = ns.split '/'

            startJ = bundleParts.length - nsParts.length
            for i in [0..nsParts.length-1]
              bundleParts[startJ+i] = nsParts[i]

            bundleSpec = bundleParts.join '/'
      else
        bundleSpec = '/cord/core' if not bundleSpec?
        relativePath = name

    nameParts = relativePath.split '/'
    templateName = nameParts.pop()

    result =
      bundle: bundleSpec
      templateName: templateName
      canonicalPath: "#{ bundleSpec }//#{ relativePath }"
      relativeFilePath: "#{ bundleSpec.substr(1) }/templates/#{ relativePath }"


  load: (name, req, load, config) ->
    info = @getFullInfo name
    if dust.cache[info.canonicalPath]?
      dust.cache[name] = dust.cache[info.canonicalPath]
      load dust.cache[name]
    else
      req ["text!#{ config.paths.pathBundles }/#{ info.relativeFilePath }.html"], (tmplString) ->
        dust.loadSource dust.compile(tmplString, info.canonicalPath)
        dust.cache[name] = dust.cache[info.canonicalPath]
        load dust.cache[name]

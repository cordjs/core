define [
  'dustjs-helpers'
  'pathUtils'
], (dust, pathUtils) ->

  getFullInfo: (name) ->
    info = pathUtils.parsePathRaw(name)
    bundleSpec = info.bundle
    relativePath = info.relativePath

    nameParts = relativePath.split '/'
    templateName = nameParts.pop()

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
      req ["text!#{ config.paths.bundles }/#{ info.relativeFilePath }.html"], (tmplString) ->
        dust.loadSource dust.compile(tmplString, info.canonicalPath)
        dust.cache[name] = dust.cache[info.canonicalPath]
        load dust.cache[name]

define ['pathUtils'], (pathUtils) ->

  classNameFormat: /^[A-Z][A-Za-z0-9]*$/


  getFullInfo: (name) ->
    info = pathUtils.parsePathRaw(name)
    bundleSpec = info.bundle
    relativePath = info.relativePath

    nameParts = relativePath.split '/'
    className = nameParts.pop()
    if not @classNameFormat.test(className)
      throw new Error("Model(repo) class name should start with CAP letter: #{ className }!")

    relativeDir = nameParts.join('/')
    relativeDirPath = "#{ bundleSpec.substr(1) }/models/#{ relativeDir }"

    bundle: bundleSpec
    className: className
    canonicalPath: "#{ bundleSpec }//#{ relativePath }"
    relativeDirPath: relativeDirPath
    relativeFilePath: "#{ relativeDirPath }/#{ className }"


  load: (name, req, load, config) ->
    info = @getFullInfo name
    req ["#{ config.paths.bundles }/#{ info.relativeFilePath }"], (ModelClass) ->
      ModelClass.path = info.canonicalPath
      ModelClass.bundle = info.bundle
      load ModelClass

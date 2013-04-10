define [
  'cord!configPaths'
], (configPaths) ->

  classNameFormat: /^[A-Z][A-Za-z0-9]*$/


  getFullInfo: (name) ->
    info = configPaths.parsePathRaw(name)
    bundleSpec = info.bundle
    relativePath = info.relativePath

    nameParts = relativePath.split '/'
    className = nameParts.pop()
    if not @classNameFormat.test(className)
      throw new Error("Model(repo) class name should start with CAP letter: #{ className }!")

#    if className.substr(-4) == 'Repo'
#      modelName = className.slice(0, -4)
#    else
#      modelName = className
#    dirName = modelName.charAt(0).toLowerCase() + modelName.slice(1)
#    nameParts.push(dirName)
    relativeDir = nameParts.join('/')
    relativeDirPath = "#{ bundleSpec.substr(1) }/models/#{ relativeDir }"

    bundle: bundleSpec
    className: className
#    dirName: dirName
    canonicalPath: "#{ bundleSpec }//#{ relativePath }"
    relativeDirPath: relativeDirPath
    relativeFilePath: "#{ relativeDirPath }/#{ className }"


  load: (name, req, load, config) ->
    info = @getFullInfo name
    req ["#{ config.paths.pathBundles }/#{ info.relativeFilePath }"], (ModelClass) ->
      ModelClass.bundle = info.bundle
      load ModelClass

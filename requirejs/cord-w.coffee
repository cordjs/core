define ['pathUtils'], (pathUtils) ->

  classNameFormat: /^[A-Z][A-Za-z0-9]*$/

  getFullInfo: (name) ->
    info = pathUtils.parsePathRaw(name)
    bundleSpec = info.bundle
    relativePath = info.relativePath

    nameParts = relativePath.split '/'
    widgetClassName = nameParts.pop()
    if not @classNameFormat.test(widgetClassName)
      throw new Error("Widget class name should start with CAP letter: #{ widgetClassName }!")
    dirName = widgetClassName.charAt(0).toLowerCase() + widgetClassName.slice(1)
    nameParts.push(dirName)
    relativeDir = nameParts.join('/')
    relativeDirPath = "#{ bundleSpec.substr(1) }/widgets/#{ relativeDir }"

    bundle: bundleSpec
    className: widgetClassName
    dirName: dirName
    canonicalPath: "#{ bundleSpec }//#{ relativePath }"
    relativeDirPath: relativeDirPath
    relativeFilePath: "#{ relativeDirPath }/#{ widgetClassName }"


  load: (name, req, load, config) ->
    info = @getFullInfo name
    req ["#{ config.paths.bundles }/#{ info.relativeFilePath }"], (WidgetClass) ->
      if !WidgetClass
        throw new Error("Cannot determine WidgetClass: #{name}! Required url: " +
          "#{ config.paths.bundles }/#{ info.relativeFilePath }")
      WidgetClass.path = info.canonicalPath
      WidgetClass.bundle = info.bundle
      WidgetClass.relativeDirPath = info.relativeDirPath
      WidgetClass.dirName = info.dirName
      WidgetClass._initialized = false
      load WidgetClass

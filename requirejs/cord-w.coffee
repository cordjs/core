define ['pathUtils'], (pathUtils) ->

  classNameFormat: /^[A-Z][A-Za-z0-9]*$/

  getFullInfo: (name) ->
    info = pathUtils.parsePathRaw(name)
    bundleSpec = info.bundle
    relativePath = info.relativePath

    nameParts = relativePath.split '/'
    widgetClassName = nameParts.pop()
    if not @classNameFormat.test(widgetClassName)
      throw new Error("Widget class name should start with CAP letter: #{widgetClassName}! Parsed name: #{name}.")
    dirName = widgetClassName.charAt(0).toLowerCase() + widgetClassName.slice(1)
    nameParts.push(dirName)
    relativeDir = nameParts.join('/')
    relativeDirPath = "#{ bundleSpec.substr(1) }/widgets/#{ relativeDir }"

    bundle: bundleSpec
    className: widgetClassName
    dirName: dirName
    canonicalPath: "#{ bundleSpec }//#{ relativePath }"
    relativeDir: relativeDir
    relativeDirPath: relativeDirPath
    relativeFilePath: "#{ relativeDirPath }/#{ widgetClassName }"


  load: (name, req, load, config) ->
    try
      info = @getFullInfo(name)
      req ["#{ config.paths.bundles }/#{ info.relativeFilePath }"], (WidgetClass) ->
        if WidgetClass
          WidgetClass.path = info.canonicalPath
          WidgetClass.bundle = info.bundle
          WidgetClass.relativeDirPath = info.relativeDirPath
          WidgetClass.dirName = info.dirName
          WidgetClass.relativeDir = info.relativeDir
          load WidgetClass
        else
          load.error(new Error(
            "Invalid WidgetClass for #{name}: #{WidgetClass}! " +
              "Required path: #{ config.paths.bundles }/#{ info.relativeFilePath }"
          ))
    catch err
      load.error(err)

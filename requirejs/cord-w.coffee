define [], ->

  classNameFormat: /[A-Z][A-Za-z0-9]*/

  getFullInfo: (name) ->
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
    widgetClassName = nameParts.pop()
    throw "Widget class name should start with CAP letter: #{ widgetClassName }!" if not @classNameFormat.test widgetClassName
    dirName = widgetClassName.charAt(0).toLowerCase() + widgetClassName.slice(1)
    nameParts.push(dirName)
    relativeDir = nameParts.join('/')
    relativeDirPath = "#{ bundleSpec.substr(1) }/widgets/#{ relativeDir }"

    result =
      bundle: bundleSpec
      className: widgetClassName
      dirName: dirName
      canonicalPath: "#{ bundleSpec }//#{ relativePath }"
      relativeDirPath: relativeDirPath
      relativeFilePath: "#{ relativeDirPath }/#{ widgetClassName }"


  load: (name, req, load, config) ->
    info = @getFullInfo name
#    console.log "cord-w::load( #{name} ) -> #{info.canonicalPath}, #{info.relativeFilePath}"
    req ["#{ config.paths.pathBundles }/#{ info.relativeFilePath }"], (WidgetClass) ->
      WidgetClass.path = info.canonicalPath
      WidgetClass.bundle = info.bundle
      WidgetClass.relativeDirPath = info.relativeDirPath
      WidgetClass.dirName = info.dirName
      load WidgetClass

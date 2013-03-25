define [
  'cord-w'
  'cord!configPaths'
], (cordWidgetHelper,configPaths) ->

  class Helper
    ###
    Helper functions for the css-file management
    ###

    getHtmlLink: (path) ->
      ###
      Returns link-tag html for the given css file
      ###
      "<link href=\"#{ path }\" rel=\"stylesheet\" />"


    expandPath: (shortPath, contextWidget) ->
      ###
      Translates given short path of the css for the given widget into full path to css file for the browser
      @param String shortPath
      @param Widget contextWidget
      @return String
      ###
      result = null
      if shortPath.substr(0, 1) != '/' and shortPath.indexOf '//' == -1
        # context of current widget
        shortPath += '.css' if shortPath.substr(-4) != '.css'
        result = "/bundles/#{ contextWidget.getDir() }/#{ shortPath }"
      else
        if shortPath.substr(0,8) == '/vendor/'
          shortPath += '.css' if shortPath.substr(-4) != '.css'
          result = shortPath
        else
          # canonical path format
          info = configPaths.parsePathRaw "#{ shortPath }@#{ contextWidget.getBundle() }"

          relativePath = info.relativePath
          nameParts = relativePath.split '/'
          widgetClassName = nameParts.pop()
          if cordWidgetHelper.classNameFormat.test widgetClassName
            dirName = widgetClassName.charAt(0).toLowerCase() + widgetClassName.slice(1)
            nameParts.push(dirName)
            relativePath = nameParts.join('/') + "/#{ dirName }.css"
          else
            relativePath += '.css' if relativePath.substr(-4) != '.css'

          result = "/bundles#{ info.bundle }/widgets/#{ relativePath }"
      "#{ result }?uid=#{ (new Date).getTime() }"


  new Helper

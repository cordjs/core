define [
  'cord-w'
  'cord!utils/Future'
  'pathUtils'
  'underscore'
], (cordWidgetHelper, Future, pathUtils, _) ->

  class Helper
    ###
    Helper functions for the css-file management
    ###

    _cssToGroupFuture: null

    _getCssToGroup: ->
      ###
      Loads map with group-id for each css-file from the preliminarily saved file.
      @return Future[Map[String, String]
      @server-only
      ###
      if not @_cssToGroupFuture
        @_cssToGroupFuture =
          if global.config.browserInitScriptId
            Future.require('fs').flatMap (fs) ->
              r = Future.single()
              fs.exists 'conf/css-to-group-generated.js', (exists) ->
                r.resolve(exists)
              r
            .flatMap (exists) ->
              if exists
                Future.require('../conf/css-to-group-generated')
              else
                # if the generated file doesn't exists, just disabling CSS group loading
                Future.resolved({})
            .failAloud('CssHelper::_getCssToGroup')
          else
            Future.resolved({})
      @_cssToGroupFuture


    getHtmlLink: (path) ->
      ###
      Returns link-tag html for the given css file
      ###
      "<link href=\"#{ path }\" rel=\"stylesheet\" />"


    getInitCssCode: (cssList) ->
      ###
      Generates html head fragment with css-link tags that should be included for server-side generated page.
      Uses group optimization to map the files.
      @param Array[String] cssList list of required css-files for the page.
      @return Future[String]
      ###
      @_getCssToGroup().map (cssToGroup) =>
        optimized =
          for css in cssList
            if cssToGroup[css]
              "/assets/z/#{cssToGroup[css]}.css"
            else
              # anti-cache suffix is needed only for direct-links, not for the optimized groups
              "#{css}?release=#{ global.config.static.release }"
        _.map(_.uniq(optimized), @getHtmlLink).join('')


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
          info = pathUtils.parsePathRaw "#{ shortPath }@#{ contextWidget.getBundle() }"

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
      result


  new Helper

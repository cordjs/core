define [
  'cord-w'
  'cord!utils/Future'
  'pathUtils'
  'underscore'
], (cordWidgetHelper, Future, pathUtils, _) ->

  getBaseUrl = -> if global.config?.localFsMode then '' else '/'

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
            Future.require('fs').then (fs) ->
              # check file existence, avoiding using of deprecated fs.exists
              # this check is needed because requirejs file existence error is not catchable in nodejs environment
              Future.call(fs.stat, 'conf/css-to-group-generated.js').catch ->
                # dirty workaround for the edge case when index.html is rendered in cordjs builder environment
                Future.call(fs.stat, 'target/conf/css-to-group-generated.js')
              .then -> true
              .catch -> false
            .then (exists) ->
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
      baseUrl = getBaseUrl()
      @_getCssToGroup().then (cssToGroup) =>
        optimized =
          for css in cssList
            css = normalizePath(css)
            if cssToGroup[css]
              "#{baseUrl}assets/z/#{cssToGroup[css]}.css"
            else
              # anti-cache suffix is needed only for direct-links, not for the optimized groups
              "#{baseUrl}#{css}?release=#{global.config.static.release}"
        _.map(_.uniq(optimized), @getHtmlLink).join('')


    expandPath: (shortPath, contextWidget) ->
      ###
      Translates given short path of the css for the given widget into full path to css file for the browser
      @param String shortPath
      @param Widget contextWidget
      @return String
      ###
      throw new Error("Css path: '#{shortPath}' is not a string.") if not _.isString(shortPath)
      baseUrl = getBaseUrl()
      if shortPath.charAt(0) != '/' and shortPath.indexOf '//' == -1
        # context of current widget
        shortPath += '.css' if shortPath.substr(-4) != '.css'
        "#{baseUrl}bundles/#{contextWidget.getDir()}/#{shortPath}"
      else
        if shortPath.substr(0,8) == '/vendor/'
          shortPath += '.css' if shortPath.substr(-4) != '.css'
          if global.config.localFsMode then shortPath.substr(1) else shortPath
        else
          # canonical path format
          info = pathUtils.parsePathRaw "#{ shortPath }@#{ contextWidget.getBundle() }"

          relativePath = info.relativePath
          nameParts = relativePath.split('/')
          widgetClassName = nameParts.pop()
          if cordWidgetHelper.classNameFormat.test widgetClassName
            dirName = widgetClassName.charAt(0).toLowerCase() + widgetClassName.slice(1)
            nameParts.push(dirName)
            relativePath = nameParts.join('/') + "/#{ dirName }.css"
          else
            relativePath += '.css' if relativePath.substr(-4) != '.css'

          "#{baseUrl}bundles#{info.bundle}/widgets/#{relativePath}"



  normalizePath = (path) ->
    ###
    Cuts query params and leading slash from the css path
    ###
    start = if path.charAt(0) == '/' then 1 else 0
    idx = path.indexOf('?')
    end = if idx == -1 then undefined else idx
    path.slice(start, end)


  new Helper

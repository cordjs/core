define [
  'cord-w'
  'dustjs-helpers'
  'cord!requirejs/pathConfig'
  'cord!utils/Future'
], (cord, dust, pathConfig, Future) ->

  loadWidgetTemplate: (path) ->
    ###
    Loads widget's template source into dust. Returns a Future which is completed when template is loaded.
    @return Future()
    ###
    if dust.cache[path]?
      Future.resolved()
    else
      info = cord.getFullInfo(path)
      Future.require("#{ pathConfig.bundles }/#{ info.relativeDirPath }/#{ info.dirName }.html")


  loadAdditionalTemplate: (path, templateName) ->
    ###
    Loads additional widget template
    @params String path - widgets full path
    @params String templatename - additional template file name without any extansions
    @return Future()
    ###
    info = cord.getFullInfo(path)
    if dust.cache["cord!/#{ info.relativeDirPath }/#{ templateName }"]
      Future.resolved()
    else
      Future.require("cord!/#{ info.relativeDirPath }/#{ templateName }.html")


  loadTemplate: (path, callback) ->
    ###
    dustjs.onLoad handler
    ###
    if path.indexOf('!') == -1
      fullPath = "cord-t!" + path
    else
      fullPath = path + '.html'
    require [fullPath], ->
      callback()


  loadToDust: (path) ->
    ###
    Loads compiled dust template from the given path into the dust cache.
    Path is considered as relative to 'bundles' root, but must begin with slash (/).
    @return Future()
    ###
    if dust.cache[path]?
      Future.resolved()
    else
      Future.require("#{ pathConfig.bundles }/#{ path }")

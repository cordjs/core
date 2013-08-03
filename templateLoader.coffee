define [
  'cord-w'
  'dustjs-helpers'
  'cord!configPaths'
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
      Future.require("text!#{ pathConfig.paths.pathBundles }/#{ info.relativeDirPath }/#{ info.dirName }.html.js")
        .andThen (err, tmplString) ->
          throw err if err
          dust.loadSource tmplString, path

  loadTemplate: (path, callback) ->
    require ["cord-t!" + path], ->
      callback()

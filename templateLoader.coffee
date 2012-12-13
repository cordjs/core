define [
  'cord-w'
  'dustjs-helpers'
  'cord!configPaths'
], (cord, dust, pathConfig) ->

  loadWidgetTemplate: (path, callback) ->
    console.log "loadWidgetTemplate(#{path})" if global.CONFIG.debug?.widget
    info = cord.getFullInfo path
    require ["text!#{ pathConfig.paths.pathBundles }/#{ info.relativeDirPath }/#{ info.dirName }.html.js"], (tmplString) ->
      dust.loadSource tmplString, path
      callback()

  loadTemplate: (path, callback) ->
    require ["cord-t!" + path], ->
      callback()

define [
  'cord-w',
  'dustjs-linkedin'
], (cord, dust) ->

  load: (name, req, load, config) ->
    info = cord.getFullInfo name
    req ["text!#{ config.paths.pathBundles }/#{ info.relativeDirPath }/#{ info.dirName }.html.js"], (tmplString) ->
      dust.loadSource tmplString, name
      load dust.cache[name]

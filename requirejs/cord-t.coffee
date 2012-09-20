define ['cord-w'], (cord) ->

  load: (name, req, load, config) ->
    info = cord.getFullInfo name
    req ["text!#{ config.paths.pathBundles }/#{ info.relativeDirPath }/#{ info.dirName }.html"], (data) ->
      load data

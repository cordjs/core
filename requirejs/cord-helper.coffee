`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], () ->
  cord =
    getPath: (name, config) ->
      if name.substr(0, 2) is '//'
        name = "#{ config.paths.ProjectNS }/widgets/#{ name.substr(2) }"
      else if name.substr(0, 1) is '/'
        name = "#{ config.paths.pathBundles }#{name}"
      name
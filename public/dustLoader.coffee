`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'underscore'
  'requirejs'
], (dust, _, requirejs) ->

  dust.onLoad = (tmplPath, callback) ->
    requirejs ['fs'], (fs) ->
      fs.readFile tmplPath, 'utf8', (err, tmplString) ->
        callback err, tmplString
#    require ["text!" + tmplPath], (tplString) ->
#      callback null, tplString

  class DustLoader

    loadTemplate: (path, name, callback) ->
      if _.isFunction name
        callback = name
        name = @_getAutoName path
      else
        name = if name then name else @_getAutoName path

      requirejs ['fs'], (fs) ->
        fs.readFile path, 'utf8', (err, data) ->
          if err then throw err
          dust.loadSource(dust.compile data, name)
          callback()


    _getAutoName: (path) ->
      path
#      split = path.split('.')[0].split('/')
#      split[split.length-1]

  new DustLoader
`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'underscore'
  'requirejs'
], (dust, _, requirejs) ->

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
    split = path.split('.')[0].split('/')
    split[split.length-1]

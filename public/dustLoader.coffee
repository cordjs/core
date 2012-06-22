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

    console.log "preved"

    requirejs ['fs'], (fs) ->
      console.log "medved"
      fs.readFile path, 'utf8', (err, data) ->
        console.log "preved"
        if err then throw err
        dust.loadSource(dust.compile data, name)
        console.log "dust path read #{ path }"
        callback()


  _getAutoName: (path) ->
    split = path.split('.')[0].split('/')
    split[split.length-1]

`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'underscore'
], (dust, _) ->

  requireFunction = if window? then require else requirejs

  dust.onLoad = (tmplPath, callback) ->
      if tmplPath.substr(0,1) is '/'
        tmplPath = tmplPath.substr(1)

      requireFunction ["text!" + tmplPath], (tplString) ->
        callback null, tplString

  class DustLoader

    loadTemplate: (path, name, callback) ->
      if _.isFunction name
        callback = name
        name = @_getAutoName path
      else
        name = if name then name else @_getAutoName path

      dustCompileCallback = (err, data) ->
        if err then throw err
        dust.loadSource(dust.compile data, name)
        callback()

      requireFunction ["text!" + path], (tplString) ->
        dustCompileCallback null, tplString

    _getAutoName: (path) ->
      path
#      split = path.split('.')[0].split('/')
#      split[split.length-1]

  new DustLoader
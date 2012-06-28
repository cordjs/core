`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'underscore'
  'requirejs'
], (dust, _, requirejs) ->

#  isNode = false
#  if typeof module != 'undefined' and module.exports?
#    isNode = true
  isNode = ! window?
  console.log 'isNode', isNode

  dust.onLoad = (tmplPath, callback) ->
    if isNode
      requirejs ['fs'], (fs) ->
        fs.readFile 'public' + tmplPath, 'utf8', (err, tmplString) ->
          callback err, tmplString
    else
      require ["text!" + tmplPath], (tplString) ->
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

      if isNode
        requirejs ['fs'], (fs) ->
          fs.readFile 'public' + path, 'utf8', dustCompileCallback
      else
        require ["text!" + path], (tplString) ->
          dustCompileCallback null, tplString


    _getAutoName: (path) ->
      path
#      split = path.split('.')[0].split('/')
#      split[split.length-1]

  new DustLoader
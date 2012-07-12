`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'module'
], (module) ->
  {
    load: (name, req, onLoad, config) ->
      req ["cord!#{ name }"], (path) ->
        req ["text!#{ path }"], (data) ->
          onLoad data
  }

`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'module'
  'cord-helper'
], (module, helper) ->
  cord =
    load: (name, req, onLoad, config) ->
      path = helper.getPath name, config
      req [path], (data) ->
        onLoad data

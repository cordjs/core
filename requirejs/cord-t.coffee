define [
  'module'
  'cord-helper'
], (module, helper) ->
  cord =

    load: (name, req, onLoad, config) ->
      path = helper.getPath name, config, module.id
      req ["text!#{ path }.html"], (data) ->
        onLoad data

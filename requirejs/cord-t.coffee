define [
  'module'
  'cord-helper'
], (module, helper) ->
  cord =

    load: (name, req, onLoad, config) ->
      path = helper.getPath name, config, module.id
      path = "#{ path }.html" if ! (path.split('.').pop().length <= 4)
      req ["text!#{ path }"], (data) ->
        onLoad data

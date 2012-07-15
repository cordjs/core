define [
  'module'
  'cord-helper'
], (module, helper) ->
  cord =

    load: (name, req, onLoad, config) ->
      path = helper.getPath name, config
      req [path], (data) ->
        onLoad data
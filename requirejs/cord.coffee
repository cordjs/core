define ['cord-helper'], (helper) ->

  load: (name, req, onLoad, config) ->
    path = helper.getPath name, config, 'cord'
    req [path], (data) ->
      onLoad data

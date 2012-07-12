`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'url'
  'Router'
  'widgetInitializer'
], (url, Router, widgetInitializer) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url

      @setPath req.url

      if (route = @matchRoute path.pathname)
        console.log "router.process #{ req.url } #{ path.pathname }"

        rootWidgetPath = if route.widget? then route.widget else @rootWidget
        action = route.action
        params = route.params

        requirejs [rootWidgetPath], (RootWidgetClass) =>
          res.writeHead 200, 'Content-Type': 'text/html'
          rootWidget = new RootWidgetClass;
          widgetInitializer.setRootWidget rootWidget

          rootWidget.showAction action, params, (err, output) ->
            if err then throw err
            res.end output

        true
      else
        false


  new ServerSideRouter
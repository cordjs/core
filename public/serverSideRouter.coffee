`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'url'
  './Router'
], (url, Router) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url

      @setPath req.url

      if (route = @matchRoute path.pathname)
        console.log "router.process #{ req.url } #{ path.pathname }"

        rootWidgetPath = route.widget
        action = route.action
        params = route.params

        requirejs [rootWidgetPath, './widgetInitializer'], (RootWidgetClass, widgetInitializer) =>
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
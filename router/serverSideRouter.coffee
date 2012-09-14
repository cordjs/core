define [
  'url'
  'cord!/cord/core/router/Router'
  'cord!/cord/core/widgetInitializer'
], (url, Router, widgetInitializer) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url

      @setPath req.url

      if (route = @matchRoute path.pathname)

        rootWidgetPath = if route.widget? then route.widget else @defWidget
        action = route.action
        params = route.params

        @setCurrentBundle rootWidgetPath

        require [
          "cord-w!#{ rootWidgetPath }"
          'cord!widgetCompiler'
        ], (RootWidgetClass, widgetCompiler) =>
          res.writeHead 200, 'Content-Type': 'text/html'
          rootWidget = new RootWidgetClass true
          rootWidget.setPath? rootWidgetPath
#          rootWidget.setBundle if route.currentBundle? then route.currentBundle else ""

          # todo: temporary!!! do not commit!
          widgetCompiler.reset()

          widgetInitializer.setRootWidget rootWidget

          rootWidget.showAction action, params, (err, output) ->
            if err then throw err
            widgetCompiler.printStructure()
            res.end widgetCompiler.getStructureCode()
          , req, res

        true
      else
        false


  new ServerSideRouter

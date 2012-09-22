define [
  'url'
  'cord!/cord/core/router/Router'
  'cord!/cord/core/widgetRepo'
  'underscore'
], (url, Router, widgetRepo, _) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url, true

      @setPath req.url

      if (route = @matchRoute path.pathname)

        rootWidgetPath = if route.widget? then route.widget else @defWidget
        action = route.action
        params = _.extend path.query, route.params

        widgetRepo.createWidget rootWidgetPath, (rootWidget) ->
          res.writeHead 200, 'Content-Type': 'text/html'

          rootWidget._isExtended = true
          widgetRepo.setRootWidget rootWidget

          rootWidget.showAction action, params, (err, output) ->
            if err then throw err
            res.end output

        true
      else
        false


  new ServerSideRouter

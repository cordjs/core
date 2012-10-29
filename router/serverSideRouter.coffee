define [
  'url'
  'cord!/cord/core/router/Router'
  'cord!WidgetRepo'
  'underscore'
], (url, Router, WidgetRepo, _) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url, true

      @setPath req.url

      if (route = @matchRoute path.pathname)

        rootWidgetPath = if route.widget? then route.widget else @defWidget
        action = route.action
        params = _.extend path.query, route.params

        widgetRepo = new WidgetRepo
        widgetRepo.setRequest req
        widgetRepo.setResponse res
        widgetRepo.createWidget rootWidgetPath, (rootWidget) ->
          rootWidget._isExtended = true
          widgetRepo.setRootWidget rootWidget

          rootWidget.showAction action, params, (err, output) ->
            if err then throw err
            res.writeHead 200, 'Content-Type': 'text/html'
            res.end output
            # todo: may be need some cleanup before?
            widgetRepo = null

        true
      else
        false


  new ServerSideRouter

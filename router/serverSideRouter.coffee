define [
  'cord!AppConfigLoader'
  'cord!router/Router'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'cord!utils/DomInfo'
  'underscore'
  'url'
], (AppConfigLoader, Router, ServiceContainer, WidgetRepo, DomInfo, _, url) ->

  class ServerSideRouter extends Router

    process: (req, res, fallback = false) ->
      path = url.parse(req.url, true)

      @currentPath = req.url

      if (routeInfo = @matchRoute(path.pathname))

        rootWidgetPath = routeInfo.route.widget
        routeCallback = routeInfo.route.callback
        params = _.extend(path.query, routeInfo.params)

        serviceContainer = new ServiceContainer
        serviceContainer.set 'container', serviceContainer

        ###
          Другого места получить из первых рук запрос-ответ нет
        ###

        serviceContainer.set 'serverRequest', req
        serviceContainer.set 'serverResponse', res
        serviceContainer.set 'router', this

        ###
          Конфиги
        ###
        global.appConfig.browser.calculateByRequest?(req)
        global.appConfig.node.calculateByRequest?(req)

        widgetRepo = new WidgetRepo

        clear = =>
          if serviceContainer?
            serviceContainer.eval 'oauth2', (oauth2) =>
              oauth2.clear()

          serviceContainer.set 'router', null
          serviceContainer = null
          widgetRepo = null
          rootWidget = null

        config = global.config
        config.api.authenticateUserCallback = ->
          if serviceContainer
            response = serviceContainer.get 'serverResponse'
            request = serviceContainer.get 'serverRequest'
            if !response.alreadyRelocated
              response.shouldKeepAlive = false
              response.alreadyRelocated = true
              response.writeHead 302,
                "Location": '/user/login/?back=' + request.url
                "Cache-Control" : "no-cache, no-store, must-revalidate"
                "Pragma": "no-cache"
                "Expires": 0
              response.end()
              clear()
          false

        serviceContainer.set 'config', config

        serviceContainer.set 'widgetRepo', widgetRepo
        widgetRepo.setServiceContainer(serviceContainer)

        widgetRepo.setRequest(req)
        widgetRepo.setResponse(res)

        eventEmitter = @eventEmitter

        AppConfigLoader.ready().done (appConfig) ->
          for serviceName, info of appConfig.services
            do (info) ->
              serviceContainer.def serviceName, info.deps, (get, done) ->
                info.factory.call(serviceContainer, get, done)

          previousProcess = {}

          processWidget = (rootWidgetPath, params) =>
            if previousProcess.showPromise
              previousProcess.showPromise.clearAllCallbacks()

            widgetRepo.createWidget rootWidgetPath, (rootWidget) ->
              rootWidget._isExtended = true
              widgetRepo.setRootWidget(rootWidget)
              previousProcess.showPromise = rootWidget.show(params, DomInfo.fake())
              previousProcess.showPromise.failAloud().done (out) ->
                #prevent browser to use the same connection
                res.shouldKeepAlive = false
                res.writeHead 200, 'Content-Type': 'text/html'
                res.end(out)
                # todo: may be need some cleanup before?
                clear()

          eventEmitter.once 'fallback', (args) =>
            # Clear previous root widget
            if widgetRepo.getRootWidget()
              widgetRepo.dropWidget widgetRepo.getRootWidget().ctx.id

            processWidget args.widgetPath, args.params

          if rootWidgetPath?
            processWidget rootWidgetPath, params


          else if routeCallback?
            routeCallback
              serviceContainer: serviceContainer
              params: params
            , =>
              res.end()
              clear()
          else
            res.shouldKeepAlive = false
            res.writeHead 404, 'Content-Type': 'text/html'
            res.end 'Error 404'
            clear()
        true
      else
        false


    fallback: (widgetPath, params) ->
      #TODO: find better way to change root widget
      @eventEmitter.emit 'fallback',
        widgetPath:widgetPath,
        params:params


  new ServerSideRouter

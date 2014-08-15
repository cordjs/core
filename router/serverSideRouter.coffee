define [
  'cord!AppConfigLoader'
  'cord!router/Router'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'cord!utils/DomInfo'
  'underscore'
  'url'
], (AppConfigLoader, Router, ServiceContainer, WidgetRepo, DomInfo, _, url) ->

  class ServerSideFallback

    constructor: (@eventEmitter) ->

    fallback: (widgetPath, params) ->
      #TODO: find better way to change root widget
      @eventEmitter.emit 'fallback',
        widgetPath: widgetPath,
        params: params



  class ServerSideRouter extends Router

    process: (req, res, fallback = false) ->
      path = url.parse(req.url, true)

      @_currentPath = req.url

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
            for serviceName in serviceContainer.getNames()
              if serviceContainer.isReady(serviceName)
                serviceContainer.eval serviceName, (service) ->
                  service.clear?()

            serviceContainer.set 'router', null
            serviceContainer = null
          widgetRepo = null

        config = global.config
        loginUrl = config.api.loginUrl or 'user/login'
        logoutUrl = config.api.logoutUrl or 'user/logout'
        config.api.authenticateUserCallback = =>
          if serviceContainer
            response = serviceContainer.get 'serverResponse'
            request = serviceContainer.get 'serverRequest'
            if not (request.url.indexOf(loginUrl) >= 0 or request.url.indexOf(logoutUrl) >= 0)
              @redirect("/#{loginUrl}/?back=#{request.url}", response)
              clear()
          false

        serviceContainer.set 'config', config

        serviceContainer.set 'widgetRepo', widgetRepo
        widgetRepo.setServiceContainer(serviceContainer)

        widgetRepo.setRequest(req)
        widgetRepo.setResponse(res)

        eventEmitter = new @EventEmitter()
        fallback = new ServerSideFallback(eventEmitter)

        serviceContainer.set 'fallback', fallback

        AppConfigLoader.ready().done (appConfig) ->
          for serviceName, info of appConfig.services
            do (info) ->
              serviceContainer.def serviceName, info.deps, (get, done) ->
                info.factory.call(serviceContainer, get, done)

          previousProcess = {}

          processWidget = (rootWidgetPath, params) =>
            widgetRepo.createWidget(rootWidgetPath).then (rootWidget) ->
              rootWidget._isExtended = true
              widgetRepo.setRootWidget(rootWidget)
              previousProcess.showPromise = rootWidget.show(params, DomInfo.fake())
              previousProcess.showPromise.done (out) ->
                eventEmitter.removeAllListeners('fallback')
                # prevent browser to use the same connection
                res.shouldKeepAlive = false
                res.writeHead 200, 'Content-Type': 'text/html'
                res.end(out)
                # todo: may be need some cleanup before?
                clear()
            .failAloud("ServerSideRouter::processWidget:#{rootWidgetPath}")

          eventEmitter.once 'fallback', (args) =>
            if previousProcess.showPromise
              previousProcess.showPromise.clear()

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
            , ->
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


    redirect: (redirectUrl, response) ->
      if not response.alreadyRelocated
        response.shouldKeepAlive = false
        response.alreadyRelocated = true
        response.writeHead 302,
          "Location": redirectUrl
          "Cache-Control" : "no-cache, no-store, must-revalidate"
          "Pragma": "no-cache"
          "Expires": 0
        response.end()



  new ServerSideRouter

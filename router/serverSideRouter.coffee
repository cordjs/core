define [
  'cord!AppConfigLoader'
  'cord!router/Router'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'cord!utils/DomInfo'
  'cord!utils/Future'
  'cord!utils/profiler/profiler'
  'cord!utils/sha1'
  'fs'
  if CORD_PROFILER_ENABLED then 'mkdirp' else undefined
  'underscore'
  'url'
], (AppConfigLoader, Router, ServiceContainer, WidgetRepo, DomInfo, Future, pr, sha1, fs, mkdirp, _, url) ->

  class ServerSideFallback

    constructor: (@eventEmitter, @router) ->


    defaultFallback: ->
      # If we don't need to push params into fallback widget, use default, defined in fallbackRoutes
      routeInfo = @router.matchFallbackRoute(@router.getCurrentPath())
      if routeInfo?.route?.widget?
        @fallback(routeInfo.route.widget, routeInfo.route.params)
      else
        _console.warn('defaultFallback route was not found for', @router.getCurrentPath())


    fallback: (widgetPath, params) ->
      #TODO: find better way to change root widget
      @eventEmitter.emit 'fallback',
        widgetPath: widgetPath,
        params: params



  class ServerSideRouter extends Router

    process: (req, res, fallback = false) ->
      path = url.parse(req.url, true)

      @_currentPath = req.url

      routeInfo = pr.call(this, 'matchRoute', path.pathname) # timer name is constructed automatically

      if routeInfo
        serverProfilerUid = @_initProfilerDump()

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
        appConfig = _.clone(global.appConfig)
        # second level crutch
        appConfig.browser = _.clone(global.appConfig.browser)
        appConfig.node = _.clone(global.appConfig.node)

        appConfig.browser.calculateByRequest?(req)
        appConfig.node.calculateByRequest?(req)

        widgetRepo = new WidgetRepo(serverProfilerUid)

        clear = =>
          if serviceContainer?
            for serviceName in serviceContainer.getNames()
              if serviceContainer.isReady(serviceName)
                serviceContainer.eval serviceName, (service) ->
                  service.clear?()

            serviceContainer.set 'router', null
            serviceContainer = null
          widgetRepo = null

        config = appConfig.node
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
        serviceContainer.set 'appConfig', appConfig

        serviceContainer.set 'widgetRepo', widgetRepo
        widgetRepo.setServiceContainer(serviceContainer)

        widgetRepo.setRequest(req)
        widgetRepo.setResponse(res)

        eventEmitter = new @EventEmitter()
        fallback = new ServerSideFallback(eventEmitter, this)

        serviceContainer.set 'fallback', fallback

        AppConfigLoader.ready().done (appConfig) ->
          pr.timer 'ServerSideRouter::defineServices', =>
            for serviceName, info of appConfig.services
              do (info) ->
                serviceContainer.def serviceName, info.deps, (get, done) ->
                  info.factory.call(serviceContainer, get, done)

          previousProcess = {}

          processWidget = (rootWidgetPath, params) =>
            pr.timer 'ServerSideRouter::showWidget', ->
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


    _initProfilerDump: ->
      ###
      Subscribes to current request root-timer finish to save profiling data to file to be able to transfer it
       to browser later.
      Generates and returns unique ID to link that saved file with the in-browser profiler panel.
      @return String
      ###
      if CORD_PROFILER_ENABLED
        profilerDumpDir = 'public/assets/p'
        uid = sha1(Math.random() + (new Date).getTime())
        pr.onCurrentTimerFinish (timer) ->
          dst = "#{profilerDumpDir}/#{uid}.json"
          Future.call(mkdirp, profilerDumpDir).then ->
            Future.call(fs.writeFile, dst, JSON.stringify(timer, null, 2))
          .catch (err) ->
            console.warn "Couldn't save server profiling timer [#{timer.name}]! Reason:", err
        uid
      else
        ''



  new ServerSideRouter

define [
  'cord!AppConfigLoader'
  'cord!Console'
  'cord!css/browserManager'
  'cord!router/clientSideRouter'
  'cord!PageTransition'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'jquery'
], (AppConfigLoader, _console, cssManager,
    clientSideRouter, PageTransition, ServiceContainer, WidgetRepo, $) ->

  class ClientFallback

    constructor: (@router) ->

    defaultFallback: ->
      # If we dont need to push params into fallback widget, use default, defined in fallbackRoutes
      routeInfo = @router.matchFallbackRoute(@router.getCurrentPath())
      if routeInfo?.route?.widget?
        @fallback(routeInfo.route.widget, routeInfo.params)
      else
        _console.warn('defaultFallback route was not found for', @router.getCurrentPath())


    fallback: (newWidgetPath, params) ->
      tPath = @router.getCurrentPath()
      @router.widgetRepo.transitPage(newWidgetPath, params, new PageTransition(tPath, tPath))


  -> # browserInit() function
    ###
    Initializes cordsjs core on browser-side
    ###
    serviceContainer = new ServiceContainer
    serviceContainer.def 'container', -> serviceContainer

    window._console = _console

    configInitFuture = AppConfigLoader.ready().map (appConfig) ->
      clientSideRouter.addRoutes(appConfig.routes)
      clientSideRouter.addFallbackRoutes(appConfig.fallbackRoutes)
      for serviceName, info of appConfig.services
        do (info) ->
          serviceContainer.def serviceName, info.deps, (get, done) ->
            info.factory.call(serviceContainer, get, done)

      ###
        Конфиги
      ###

      serviceContainer.def 'config', ->
        config = global.config
        loginUrl = config.loginUrl or 'user/login/'
        logoutUrl = config.logoutUrl or 'user/logout/'
        config.api.authenticateUserCallback = ->
          backPath = window.location.pathname
          if not (backPath.indexOf(loginUrl) >= 0 or backPath.indexOf(logoutUrl) >= 0)
            # in SPA mode window.location doesn't make sense
            backUrl = clientSideRouter.getCurrentPath() or window.location.pathname
            clientSideRouter.forceNavigate("#{loginUrl}?back=#{backUrl}")
          true
        config

      # Clear localStorage in case of changing collections' release number
      serviceContainer.eval 'localStorage', (localStorage) ->
        currentVersion = window.global.config.static.collection
        localStorage.getItem('collectionsVersion')
          .done (localVersion) =>
            if currentVersion != localVersion
              localStorage.clear()
              localStorage.setItem 'collectionsVersion', currentVersion
          .fail =>
            localStorage.setItem 'collectionsVersion', currentVersion


    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error) ->
      if global.config.debug.require
        throw error
      else
        _console.error 'Error from requirejs: ', error.toString(), 'Error: ', error


    widgetRepo = new WidgetRepo

    fallback = new ClientFallback(clientSideRouter)

    serviceContainer.set 'fallback', fallback
    serviceContainer.set 'router', clientSideRouter

    serviceContainer.set('widgetRepo', widgetRepo)
    widgetRepo.setServiceContainer(serviceContainer)

    clientSideRouter.setWidgetRepo(widgetRepo)
    $ ->
      cssManager.registerLoadedCssFiles()
      configInitFuture.done -> cordcorewidgetinitializerbrowser?(widgetRepo)

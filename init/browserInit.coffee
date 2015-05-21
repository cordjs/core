define [
  'cord!AppConfigLoader'
  'cord!Console'
  'cord!css/browserManager'
  'cord!router/clientSideRouter'
  'cord!PageTransition'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'cord!utils/Future'
  'monologue' + (if CORD_IS_BROWSER then '' else '.js')
  'jquery'
], (AppConfigLoader, _console, cssManager,
    clientSideRouter, PageTransition, ServiceContainer, WidgetRepo, Future, Monologue, $) ->

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


  init: -> # browserInit() function
    ###
    Initializes cordsjs core on browser-side
    ###
    serviceContainer = new ServiceContainer
    serviceContainer.def 'container', -> serviceContainer

    window._console = _console

    # support for `requireAuth` route option
    clientSideRouter.setAuthCheckCallback ->
      serviceContainer.getService('api')
        .then (api) ->
          api.prepareAuth()
        .then ->
          true
        .catch (e) ->
          _console.warn("Api.prepareAuth failed because of:", e)
          false

    console.warn("browserInit::init #{window.location.href}")

    configInitFuture = AppConfigLoader.ready().then (appConfig) ->
      console.warn("browserInit::init::clientSideRouter: #{JSON.stringify(appConfig.routes)}")
      clientSideRouter.addRoutes(appConfig.routes)
      clientSideRouter.addFallbackRoutes(appConfig.fallbackRoutes)
      for serviceName, info of appConfig.services
        do (info) ->
          throw new Error("Service '#{serviceName}' does not have a defined factory") if undefined == info.factory
          throw new Error("Service '#{serviceName}' has invalid factory definition") if not _.isFunction(info.factory)
          serviceContainer.def(serviceName, info.deps, info.factory.bind(serviceContainer))

      # `config` service definition
      serviceContainer.set 'config', global.config

      global.config.api.authenticateUserCallback = ->
        Future.all [
          serviceContainer.getService('loginUrl')
          serviceContainer.getService('logoutUrl')
        ]
        .spread (loginUrl, logoutUrl) ->
          loginUrl = loginUrl.replace(/^\/|\/$/g, "")
          logoutUrl = logoutUrl.replace(/^\/|\/$/g, "")
          backPath = clientSideRouter.getCurrentPath()
          if not (backPath.indexOf(loginUrl) >= 0 or backPath.indexOf(logoutUrl) >= 0)
            # in SPA mode window.location doesn't make sense
            backUrl = clientSideRouter.getCurrentPath() or window.location.pathname
            clientSideRouter.redirect("#{loginUrl}/?back=#{backUrl}").failAloud('Auth redirect failed!')
        .catch (error) ->
          _console.error('Unable to obtain loginUrl or logoutUrl, please, check configs:' + error)
        false

      # Clear localStorage in case of changing collections' release number
      serviceContainer.eval 'persistentStorage', (persistentStorage) ->
        currentVersion = window.global.config.static.release
        persistentStorage.get('collectionsVersion').then (localVersion) ->
          if currentVersion != localVersion
            serviceContainer.eval 'localStorage', (localStorage) ->
              localStorage.clear().then ->
                persistentStorage.set('collectionsVersion', currentVersion)


    # Global errors handling
    requirejs.onError = (error) ->
      _console.error 'Error from requirejs: ', error.toString(), 'Error: ', error
      throw error  if global.config.debug.require


    # monologue to debug mode
    Monologue.debug = true if global.config.debug.monologue != undefined and global.config.debug.monologue


    widgetRepo = new WidgetRepo(global.cordServerProfilerUid)

    fallback = new ClientFallback(clientSideRouter)

    serviceContainer.set 'fallback', fallback
    serviceContainer.set 'router', clientSideRouter

    serviceContainer.set('widgetRepo', widgetRepo)
    widgetRepo.setServiceContainer(serviceContainer)

    clientSideRouter.setWidgetRepo(widgetRepo)
    $ ->
      cssManager.registerLoadedCssFiles()
      configInitFuture.then ->
        cordcorewidgetinitializerbrowser?(widgetRepo)
      .failAloud()

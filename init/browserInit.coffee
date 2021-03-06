define [
  'cord!AppConfigLoader'
  'cord!Console'
  'cord!errors'
  'cord!css/browserManager'
  'cord!router/clientSideRouter'
  'cord!PageTransition'
  'cord!ServiceContainer'
  'cord!utils/Future'
  'monologue' + (if CORD_IS_BROWSER then '' else '.js')
  'jquery'
], (AppConfigLoader, _console, errors, cssManager,
    clientSideRouter, PageTransition, ServiceContainer, Future, Monologue, $) ->

  urlExp = /^\/|\/$/g

  class ClientFallback

    constructor: (@router, @logger) ->


    defaultFallback: ->
      # If we dont need to push params into fallback widget, use default, defined in fallbackRoutes
      routeInfo = @router.matchFallbackRoute(@router.getCurrentPath())
      if routeInfo?.route?.widget?
        @fallback(routeInfo.route.widget, routeInfo.params)
      else
        @logger.warn('defaultFallback route was not found for', @router.getCurrentPath())


    fallback: (newWidgetPath, params) ->
      tPath = @router.getCurrentPath()
      @router.widgetRepo.transitPage(newWidgetPath, params, new PageTransition(tPath, tPath))


  init: -> # browserInit() function
    ###
    Initializes cordsjs core on browser-side
    ###
    serviceContainer = new ServiceContainer
    serviceContainer.def 'serviceContainer', -> serviceContainer
    logger = serviceContainer.get('logger')

    window._console = logger

    serviceContainer.set 'router', clientSideRouter
    fallback = new ClientFallback(clientSideRouter, logger)
    serviceContainer.set 'fallback', fallback

    # support for `requireAuth` route option
    clientSideRouter.setAuthCheckCallback ->
      serviceContainer.getService('api')
        .then (api) ->
          api.prepareAuth()
        .then ->
          true
        .catch (e) ->
          logger.warn("Api.prepareAuth failed because of:", e)
          false

    $ ->
      cssManager.registerLoadedCssFiles()


    AppConfigLoader.ready().then (appConfig) ->
      clientSideRouter.addRoutes(appConfig.routes)
      clientSideRouter.addFallbackRoutes(appConfig.fallbackRoutes)
      for serviceName, info of appConfig.services
        do (info) ->
          throw new Error("Service '#{serviceName}' does not have a defined factory") if undefined == info.factory
          throw new Error("Service '#{serviceName}' has invalid factory definition") if not _.isFunction(info.factory)
          serviceContainer.def(serviceName, info.deps, info.factory.bind(serviceContainer))

      serviceContainer.set 'config', global.config

      global.config.api.authenticateUserCallback = ->
        Future.all [
          serviceContainer.getService('loginUrl')
          serviceContainer.getService('logoutUrl')
          serviceContainer.getService('authUrls')
        ]
        .spread (loginUrl, logoutUrl, authUrls) ->
          authUrls = _.clone(authUrls)
          authUrls.push(loginUrl)
          authPages = authUrls.map (url) -> url.replace(urlExp, "")
          baseLoginUrl = authPages[authPages.length - 1]
          logoutUrl = logoutUrl.replace(urlExp, "")
          backPath = clientSideRouter.getCurrentPath()
          if not (_.find(authPages, (url) -> backPath.indexOf(url) >= 0) or backPath.indexOf(logoutUrl) >= 0)
            # in SPA mode window.location doesn't make sense
            backUrl = clientSideRouter.getCurrentPath() or window.location.pathname
            clientSideRouter.redirect("#{baseLoginUrl}/?back=#{backUrl}").failAloud('Auth redirect failed!')
        .catch (error) ->
          logger.error('Unable to obtain loginUrl or logoutUrl, please, check configs:' + error)
        false

      # Clear localStorage in case of changing collections' release number
      serviceContainer.eval 'persistentStorage', (persistentStorage) ->
        currentVersion = window.global.config.static.release
        persistentStorage.get('collectionsVersion').then (localVersion) ->
          if currentVersion != localVersion
            serviceContainer.eval 'localStorage', (localStorage) ->
              localStorage.clear().then ->
                persistentStorage.set('collectionsVersion', currentVersion)

      serviceContainer.getService('widgetRepo').then (widgetRepo) ->
        clientSideRouter.setWidgetRepo(widgetRepo)
        $ ->
          cordcorewidgetinitializerbrowser?(widgetRepo)
      .failAloud()


    # Global errors handling
    requirejs.onError = (error) ->
      _console.error 'Error from requirejs: ', error.toString(), 'Error: ', error
      throw error  if global.config.debug.require


    # monologue to debug mode
    Monologue.debug = true if global.config.debug.monologue != undefined and global.config.debug.monologue

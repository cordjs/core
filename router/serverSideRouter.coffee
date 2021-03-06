define [
  'cord!AppConfigLoader'
  'cord!errors'
  'cord!router/Router'
  'cord!ServiceContainer'
  'cord!Utils'
  'cord!utils/DomInfo'
  'cord!utils/Future'
  'cord!utils/profiler/profiler'
  'cord!utils/sha1'
  'fs'
  if CORD_PROFILER_ENABLED then 'mkdirp' else undefined
  'lodash'
  'url'
  'monologue' + (if CORD_IS_BROWSER then '' else '.js')
], (AppConfigLoader, errors, Router, ServiceContainer, Utils, DomInfo, Future, pr, sha1, fs, mkdirp, _, url, Monologue) ->

  urlExp = /^\/|\/$/g

  class ServerSideFallback

    constructor: (@eventEmitter, @serviceContainer, @logger, @router) ->


    defaultFallback: ->
      # If we don't need to push params into fallback widget, use default, defined in fallbackRoutes
      currentPath = @router.getCurrentPath(@serviceContainer)
      routeInfo = @router.matchFallbackRoute(currentPath)
      if routeInfo?.route?.widget?
        @fallback(routeInfo.route.widget, routeInfo.route.params)
      else
        @logger.warn('defaultFallback route was not found for', @router.getCurrentPath())


    fallback: (widgetPath, params) ->
      #TODO: find better way to change root widget
      @eventEmitter.emit 'fallback',
        widgetPath: widgetPath,
        params: params



  class ServerSideRouter extends Router

    process: (req, res, fallback = false) ->
      path = url.parse(req.url, true)

      routeInfo = pr.call(this, 'matchRoute', path.pathname + path.search) # timer name is constructed automatically

      if routeInfo
        serverProfilerUid = @_initProfilerDump()

        rootWidgetPath = routeInfo.route.widget
        routeCallback = routeInfo.route.callback
        params = _.extend(path.query, routeInfo.params)

        serviceContainer = new ServiceContainer
        serviceContainer.set 'serviceContainer', serviceContainer
        serviceContainer.set 'serverRequest', req
        serviceContainer.set 'serverResponse', res
        serviceContainer.set 'router', this

        logger = serviceContainer.get('logger')

        # Prepare configs for particular request
        appConfig = @prepareConfigForRequest(req)

        # monologue to debug mode
        Monologue.debug = true if global.config.debug.monologue != undefined and global.config.debug.monologue

        clear = =>
          ###
          Kinda GC after request processing
          ###
          if serviceContainer?
            serviceContainer.clearServices()
            serviceContainer = null

        config = appConfig.node
        global.config = config

        serviceContainer.set 'config', config
        serviceContainer.set 'appConfig', appConfig

        config.api.authenticateUserCallback = =>
          if serviceContainer
            Future.all [
              serviceContainer.getService('loginUrl')
              serviceContainer.getService('logoutUrl')
              serviceContainer.getService('authUrls')
            ]
            .spread (loginUrl, logoutUrl, authUrls) =>
              authUrls = _.clone(authUrls)
              authUrls.push(loginUrl)
              authPages = authUrls.map (url) -> url.replace(urlExp, "")
              baseLoginUrl = authPages[authPages.length - 1]
              response = serviceContainer.get('serverResponse')
              request = serviceContainer.get('serverRequest')
              if not (_.find(authPages, (url) -> request.url.indexOf(url) >= 0))
                @redirect("/#{baseLoginUrl}/?back=#{if request.url.indexOf(logoutUrl) >= 0 then '' else request.url}", response)
                clear()
            .catch (error) ->
              logger.error('Unable to obtain loginUrl or logoutUrl, please, check configs:' + error.trace())

          false

        res.setHeader('x-info', config.static.release) if config.static.release?

        eventEmitter = new @EventEmitter()
        fallback = new ServerSideFallback(eventEmitter, serviceContainer, logger, this)

        serviceContainer.set 'fallback', fallback

        AppConfigLoader.ready().then (appConfig) ->
          pr.timer 'ServerSideRouter::defineServices', =>
            for serviceName, info of appConfig.services
              do (info) ->
                throw new Error("Service '#{serviceName}' does not have a defined factory") if undefined == info.factory
                throw new Error("Service '#{serviceName}' has invalid factory definition") if not _.isFunction(info.factory)
                serviceContainer.def(serviceName, info.deps, info.factory.bind(serviceContainer))
            serviceContainer.autoStartServices(appConfig.services)

          previousProcess = {}

          processWidget = (rootWidgetPath, params, catchError = true) ->
            pr.timer 'ServerSideRouter::showWidget', ->
              # If current route requires authorization, api service should be available
              processNext = Future.single('Main process next')
              if routeInfo.route?.requireAuth
                serviceContainer.getService('api')
                  .then => processNext.resolve()
                  # on api service failure, we should redirect user to login page
                  .catch =>
                    config.api.authenticateUserCallback()
                    processNext.clear()
              else
                processNext.resolve()

              widgetRepoPromise = serviceContainer.getService('widgetRepo').then (widgetRepo) ->
                widgetRepo.setServerProfilerUid serverProfilerUid
                widgetRepo.setRequest(req)
                widgetRepo.setResponse(res)
                widgetRepo

              Future.all [
                widgetRepoPromise
                processNext
              ]
              .spread (widgetRepo) =>
                widgetRepo.createWidget(rootWidgetPath).then (rootWidget) ->
                  if widgetRepo
                    rootWidget._isExtended = true
                    widgetRepo.setRootWidget(rootWidget)
                    previousProcess.showPromise = rootWidget.show(params, DomInfo.fake())
                    previousProcess.showPromise.done (out) ->
                      eventEmitter.removeAllListeners('fallback')
                      # prevent browser to use the same connection
                      res.shouldKeepAlive = false
                      res.writeHead 200, 'Content-Type': 'text/html'
                      res.end(out)
                .catchIf (-> catchError), (err) ->
                  if err instanceof errors.AuthError
                    # serviceContainer could be empty already
                    serviceContainer?.getService('api').then (api) ->
                      api.authenticateUser()
                  else if appConfig.errorWidget
                    processWidget(
                      appConfig.errorWidget
                      Utils.buildErrorWidgetParams(err, rootWidgetPath, params)
                      false
                    ).catch (nestedErr) =>
                      logger.error('Error handling failed because of: ', nestedErr, nestedErr.stack)
                      logger.error('Original error: ', err, err.stack)
                      throw nestedErr
                  else
                    throw err
                .catchIf (-> catchError), (err) ->
                  if not (err instanceof errors.AutoAuthError) # bypass  AutoAuthErrors
                    logger.error "FATAL ERROR: server-side rendering failed! Reason:", err, err.stack
                    displayFatalError()
                .finally ->
                  clear()


          displayFatalError = ->
            fatalErrorPageFile = 'public/' + appConfig.fatalErrorPageFile
            res.writeHead(500, 'Unexpected Error!', 'Content-type': 'text/html')
            Future.call(fs.readFile, fatalErrorPageFile, 'utf8').then (data) ->
              res.end(data)
            .catch (err) ->
              logger.error "Error while reading fatal error page html: #{err}. Falling back to the inline version.", err
              res.end """
                <html>
                  <head><title>Error 500</title></head>
                  <body><h1>Unexpected Error occurred!</h1></body>
                </html>
              """


          eventEmitter.once 'fallback', (args) ->
            if previousProcess.showPromise
              previousProcess.showPromise.clear()

            # Clear previous root widget
            serviceContainer.getService('widgetRepo').then (widgetRepo) ->
              if widgetRepo.getRootWidget()
                widgetRepo.dropWidget widgetRepo.getRootWidget().ctx.id

              processWidget(args.widgetPath, args.params)

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


    getCurrentPath: (serviceContainer) ->
      ###
      Returns current path
      @param {ServiceContainer} serviceContainer
      @return String
      ###
      serviceContainer.get('serverRequest').url


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


    prepareConfigForRequest: (request) ->
      ###
      Deep clone config and substitute {TEMPLATES}

      Examples of templates:

      {TIMESTAMP} = '1234568977'
      {NODE} = 'megaplan2.megaplan.ru:18181'
      {NODE_PROTO} = 'megaplan2.megaplan.ru:18181'
      {XDR} = if SERVER then '{NODE_PROTO}://{NODE}/XDR/' else ''

      {ACCOUNT} = 'megaplan2',
      {DOMAIN} = '.megaplan.ru',

      {BACKEND} = common.api.backend.host variable
      {BACKEND_PROTO} = common.api.backend.protocol variable
      ###

      # Prepare templates values

      # prepare what we can first
      xProto = if request.headers['x-forwarded-proto'] == 'on' then 'https' else 'http'
      ServerSideRouter.replaceConfigVarsByHost(global.appConfig, request.headers.host, xProto)


    @replaceConfigVarsByHost: (config, hostFromRequest, xProto) ->
      ###
      Deep clones config with replacement known {VARS} in string parameters
      @param config - input config object
      @param host(String)
      @param xProto - value of {X_PROTO} variable
      ###
      dotIndex = hostFromRequest.indexOf('.')

      throw new Error("Please, define the 'server' section in config.") if not config.node.server
      throw new Error("Please, define the 'api.backend' section in config.") if not config.node.api.backend

      serverHost = config.node.server.host
      serverProto = config.node.server.protocol or ''
      serverPort  = config.node.server.port

      backendProto = config.node.api.backend.protocol or 'http'

      templates =
        '{X_PROTO}': xProto
        '{TIMESTAMP}': new Date().getTime()
        '{ACCOUNT}': hostFromRequest.substr(0, dotIndex)
        '{DOMAIN}': hostFromRequest.substr(dotIndex)
        '{X_HOST}': hostFromRequest

      serverProto = Utils.substituteTemplate(serverProto, templates)
      backendProto  = Utils.substituteTemplate(backendProto, templates)

      templates['{NODE_PROTO}'] = serverProto
      templates['{BACKEND_PROTO}'] = backendProto
      templates['{NODE}'] = serverHost + (if serverPort then ':' + serverPort else '')
      templates['{NODE_HOST}'] = serverHost

      if config.browser.xdr
        xdr = Utils.substituteTemplate(config.browser.xdr, templates)
      else
        xdr = serverProto + '://' + serverHost + (if serverPort then ':' + serverPort else '') + '/XDR/'

      if config.browser.xdrs
        xdrs = Utils.substituteTemplate(config.browser.xdrs, templates)
      else
        xdrs = serverProto + '://' + serverHost + (if serverPort then ':' + serverPort else '') + '/XDRS/'

      if config.node.api.backend.host
        backend = Utils.substituteTemplate(config.node.api.backend.host, templates)
      else
        backend = hostFromRequest

      templates['{BACKEND}'] = backend
      templates['{XDR}'] = xdr
      templates['{XDRS}'] = xdrs

      context =
        templates: templates

      _.cloneDeep config, (value) ->
        Utils.substituteTemplate(value, this.templates)
      , context


  new ServerSideRouter

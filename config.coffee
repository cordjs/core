define  ->

  services:

    postal:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!/cord/core/services/Postal'], (Postal) ->
          done(null, new Postal(get('serviceContainer')))

    logger:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!/cord/core/services/Logger'], (Logger) ->
          done(null, new Logger(get('serviceContainer')))

    apiFactory:
      deps: ['runtimeConfigResolver', 'serviceContainer', 'config', 'tabSync']
      factory: (get, done) ->
        require ['cord!ApiFactory'], (ApiFactory) ->
          apiFactory = new ApiFactory()
          get('serviceContainer').injectServices(apiFactory).finally(done)

    api:
      deps: ['apiFactory', 'runtimeConfigResolver', 'config', 'logger']
      factory: (get, done) ->
        require ['cord!Api', 'postal'], (Api, postal) ->
          get('apiFactory').getApiByDefaultParams(get('config').api)
            .then (api) ->
              # Subscribe to runtimeConfigResolver's 'setParameter' event, and
              # reconfigure on event emitted
              resolver = get('runtimeConfigResolver')
              resolver.on('setParameter', -> api.configure(resolver.resolveConfig(get('config').api)))
              api.on 'host.changed', (host) ->
                if host != resolver.getParameter('BACKEND_HOST')
                  get('logger').log('BACKEND_HOST has been changed to:', host)
                  resolver.setParameter('BACKEND_HOST', host)
              api
            .then (api) ->
              postal.publish('api.available')
              api
            .finally(done)

    widgetRepo:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!WidgetRepo'], (WidgetRepo) ->
          widgetRepo = new WidgetRepo()
          get('serviceContainer').injectServices(widgetRepo).finally(done)

    tabSync:
      factory: (get, done) ->
        require ['cord!cache/TabSync' + if not CORD_IS_BROWSER then 'Server' else ''], (TabSync) ->
          tabSync = new TabSync()
          tabSync.init().finally(done)

    runtimeConfigResolver:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!RuntimeConfigResolver'], (RuntimeConfigResolver) ->
          resolver = new RuntimeConfigResolver()
          get('serviceContainer').injectServices(resolver)
            .then -> resolver.init()
            .then -> done(null, resolver)
            .catch (e) -> done(e)

    userAgent:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!/cord/core/UserAgent'], (UserAgent) =>
          userAgent = new UserAgent
          get('serviceContainer').injectServices(userAgent)
            .then ->
              userAgent.calculate()
              done(null, userAgent)
            .catch (e) -> done(e)

    modelProxy:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!/cord/core/ModelProxy'], (ModelProxy) =>
          modelProxy = new ModelProxy
          get('serviceContainer').injectServices(modelProxy)
            .then -> done(null, modelProxy)
            .catch (e) -> done(e)

    redirector:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!/cord/core/router/Redirector'], (Redirector) ->
          redirector = new Redirector()
          get('serviceContainer').injectServices(redirector)
            .then -> done(null, redirector)
            .catch (e) -> done(e)

    errorHelper:
      deps: ['serviceContainer']
      factory: (get, done) ->
        require ['cord!ErrorHelper'], (ErrorHelper) ->
          get('serviceContainer').injectServices(new ErrorHelper()).finally(done)

    ':server':
      request:
        deps: ['logger']
        factory: (get, done) ->
          require ['cord!/cord/core/request/ServerRequest'], (Request) =>
            done(null, new Request(get('logger')))

      cookie:
        deps: ['serviceContainer']
        factory: (get, done) ->
          require ['cord!/cord/core/cookie/ServerCookie'], (Cookie) =>
            done(null, new Cookie(get('serviceContainer')))

      userAgentText:
        deps: ['serverRequest']
        factory: (get, done) ->
          done(null, get('serverRequest').headers?['user-agent'])

    ':browser':
      request:
        deps: ['logger']
        factory: (get, done) ->
          require ['cord!/cord/core/request/BrowserRequest'], (Request) ->
            done(null, new Request(get('logger')))

      cookie:
        deps: ['serviceContainer', 'localStorage']
        factory: (get, done) ->
          require ["cord!/cord/core/cookie/BrowserCookie"], (Cookie) ->
            done(null, new Cookie(get('serviceContainer')))

      userAgentText: (get, done) ->
        done(null, navigator.userAgent)

      localStorage:
        deps: ['logger']
        factory: (get, done) ->
          require ['cord!cache/localStorage', 'cord!utils/Future', 'localforage'], (LocalStorage, Future, localForage) ->
            localForage.ready().then ->
              Promise::toFuture = (promise) ->
                ###
                Converts conventional "thenable" Promise into our Future promise.
                If an argument is given, then it will be fulfilled and returned instead of creating new Future promise.
                @param {Future} promise - optional externally created promise to be fulfilled with this promise result
                @return {Future}
                ###
                promise or= Future.single(':toFuture:')
                this
                  .then ->
                    promise.resolve()
                    return
                  .catch (err) ->
                    promise.reject(err)
                    return
                promise

              done(null, new LocalStorage(localForage, get('logger')))
            .catch (err) ->
              get('logger').error "ERROR while initializing localforage: #{err.message}! Driver: #{localForage.driver()}", err
              localForage.setDriver(localForage.LOCALSTORAGE).then ->
                done(null, new LocalStorage(localForage))
              .catch (err) ->
                get('logger').error "FATAL: error while initializing localforage with localStorage fallback: #{err.message}!", err

      persistentStorage:
        deps: ['localStorage']
        factory: (get, done) ->
          require ['cord!cache/persistentStorage'], (PersistentStorage) ->
            done(null, new PersistentStorage(get('localStorage')))

  routes:
    '/REQUIRESTAT/optimizer':
      widget: '//Optimizer'

  requirejs:
    paths:
      #'asap':                    'vendor/asap/asap'
      'asap/raw': 'vendor/asap/raw'
      'curly': 'vendor/curly/browser'
      'cordjs-zone': 'vendor/zone/zone'
      'dustjs-linkedin': 'vendor/dustjs/dustjs-full'
      'dustjs-helpers': 'vendor/dustjs/dustjs-helpers'
      'eventemitter3': 'vendor/eventemitter3/eventemitter3'
      'jquery': 'vendor/jquery/jquery'
      'jquery.cookie': 'vendor/jquery/plugins/jquery.cookie'
      'localforage': 'vendor/localforage/localforage'
      'monologue': 'vendor/monologue/monologue'
      'postal': 'vendor/postal/postal_lite'
      'underscore': 'vendor/underscore/underscore'
      'lodash': 'vendor/lodash/lodash'
      'riveter': 'vendor/riveter/riveter'
      'request': 'vendor/browser-request/index'
    shim:
      'curly':
        deps: ['underscore']
        exports: 'curly'
      'dustjs-linkedin':
        exports: 'dust'
      'dustjs-helpers':
        deps: ['dustjs-linkedin']
        exports: 'dust'
      'eventemitter3':
        exports: 'EventEmitter'
      'jquery.cookie':
        deps: ['jquery']
        exports: 'jQuery'
      'underscore':
        exports: '_'
      'zone':
        exports: 'zone'

  fatalErrorPageFile: 'bundles/cord/core/assets/fatal-error.html'
  errorWidget: null # You can set error widget path here in cordjs notation

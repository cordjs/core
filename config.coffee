define  ->

  services:

    apiFactory:
      deps: ['runtimeConfigResolver', 'container', 'config', 'tabSync']
      factory: (get, done) ->
        require ['cord!ApiFactory'], (ApiFactory) ->
          apiFactory = new ApiFactory(get('config').api)
          get('container').injectServices(apiFactory).finally(done)

    api:
      deps: ['apiFactory', 'runtimeConfigResolver', 'config']
      factory: (get, done) ->
        require ['cord!Api', 'postal'], (Api, postal) ->
          get('apiFactory').getApiByParams()
            .then (api) ->
              # Subscribe to runtimeConfigResolver's 'setParameter' event, and
              # reconfigure on event emitted
              resolver = get('runtimeConfigResolver')
              resolver.on('setParameter', -> api.configure(resolver.resolveConfig(get('config').api)))
              api.on 'host.changed', (host) ->
                if host != resolver.getParameter('BACKEND_HOST')
                  _console.log('BACKEND_HOST has been changed to:', host)
                  resolver.setParameter('BACKEND_HOST', host)
              api
            .then (api) ->
              done(null, api)
            .then -> postal.publish('api.available')
            .catch (e) ->
              done(e)

    tabSync:
      factory: (get, done) ->
        require ['cord!cache/TabSync' + if not CORD_IS_BROWSER then 'Server' else ''], (TabSync) ->
          tabSync = new TabSync()
          tabSync.init().finally(done)

    runtimeConfigResolver:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!RuntimeConfigResolver'], (RuntimeConfigResolver) ->
          resolver = new RuntimeConfigResolver()
          get('container').injectServices(resolver)
            .then -> resolver.init()
            .then -> done(null, resolver)
            .catch (e) -> done(e)

    userAgent:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/UserAgent'], (UserAgent) =>
          userAgent = new UserAgent
          get('container').injectServices(userAgent)
            .then ->
              userAgent.calculate()
              done(null, userAgent)
            .catch (e) -> done(e)

    modelProxy:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/ModelProxy'], (ModelProxy) =>
          modelProxy = new ModelProxy
          get('container').injectServices(modelProxy)
            .then -> done(null, modelProxy)
            .catch (e) -> done(e)

    redirector:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/router/Redirector'], (Redirector) ->
          redirector = new Redirector()
          get('container').injectServices(redirector)
            .then -> done(null, redirector)
            .catch (e) -> done(e)

    ':server':
      request:
        factory: (get, done) ->
          require ['cord!/cord/core/request/ServerRequest'], (Request) =>
            done(null, new Request)

      cookie:
        deps: ['container']
        factory: (get, done) ->
          require ['cord!/cord/core/cookie/ServerCookie'], (Cookie) =>
            done(null, new Cookie(get('container')))

      userAgentText:
        deps: ['serverRequest']
        factory: (get, done) ->
          done(null, get('serverRequest').headers?['user-agent'])

    ':browser':
      request:
        factory: (get, done) ->
          require ['cord!/cord/core/request/BrowserRequest'], (Request) ->
            done(null, new Request)

      cookie:
        deps: ['container', 'localStorage']
        factory: (get, done) ->
          require ["cord!/cord/core/cookie/BrowserCookie"], (Cookie) ->
            done(null, new Cookie(get('container')))

      userAgentText: (get, done) ->
        done(null, navigator.userAgent)

      localStorage: (get, done) ->
        require ['cord!cache/localStorage', 'cord!utils/Future', 'localforage'], (LocalStorage, Future, localForage) ->
          localForage.ready().then ->
            Promise::toFuture = (promise) ->
              ###
              Converts standart "thenable" Promise into our Future promise.
              If an argument is given, then it will be fulfilled and returned instead of creating new Future promise.
              @param {Future} promise - optional externally created promise to be fulfilled with this promise result
              @return {Future}
              ###
              promise or= Future.single(':toFuture:')
              this
                .then -> promise.resolve()
                .catch (err) -> promise.reject(err)
              promise

            done(null, new LocalStorage(localForage))
          .catch (err) ->
            _console.error "ERROR while initializing localforage: #{err.message}! Driver: #{localForage.driver()}", err
            localForage.setDriver(localForage.LOCALSTORAGE).then ->
              done(null, new LocalStorage(localForage))
            .catch (err) ->
              _console.error "FATAL: error while initializing localforage with localStorage fallback: #{err.message}!", err

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
      'asap/raw':                'vendor/asap/raw'
      'curly':                   'vendor/curly/browser'
      'cordjs-zone':             'vendor/zone/zone'
      'dustjs-linkedin':         'vendor/dustjs/dustjs-full'
      'dustjs-helpers':          'vendor/dustjs/dustjs-helpers'
      'eventemitter3':           'vendor/eventemitter3/eventemitter3'
      'jquery':                  'vendor/jquery/jquery'
      'jquery.cookie':           'vendor/jquery/plugins/jquery.cookie'
      'localforage':             'vendor/localforage/localforage'
      'monologue':               'vendor/monologue/monologue'
      'postal':                  'vendor/postal/postal_lite'
      'underscore':              'vendor/underscore/underscore'
      'lodash':                  'vendor/lodash/lodash'
      'riveter':                 'vendor/riveter/riveter'
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

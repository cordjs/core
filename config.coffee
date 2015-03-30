define ->

  services:
    apiNoWait:
      deps: ['runtimeConfigResolver', 'container', 'config']
      factory: (get) ->
        apiF = get('container').getService('api')
        get('runtimeConfigResolver').isPending('api')
          .then (isPending) ->
            if isPending
              throw new Error('Api service is unavailable now')
            else
              apiF

    api:
      deps: ['runtimeConfigResolver', 'container', 'config']
      factory: (get, done) ->
        require ['cord!Api'], (Api) ->
          container = get('container')
          get('runtimeConfigResolver')
            .resolveConfig('api', get('config').api)
              .then (apiConfig) ->
                api = new Api(container, apiConfig)
                container.injectServices(api)
                  .then -> api.init()
                  .then -> done(null, api)
              .catch (error) -> done(error)

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
          if global.config.localFsMode
            require ["cord!/cord/core/cookie/LocalCookie"], (Cookie) ->
              cookieStorage = get('localStorage')
              cookieStorage.getItem(Cookie.storageKey).then (cookies) ->
                done(null, new Cookie(cookies, cookieStorage))
              .catch ->
                done(null, new Cookie({}, cookieStorage))
          else
            require ["cord!/cord/core/cookie/BrowserCookie"], (Cookie) ->
              done(null, new Cookie(get('container')))

      userAgentText: (get, done) ->
        done(null, navigator.userAgent)

      localStorage: (get, done) ->
        require ['cord!cache/localStorage', 'localforage'], (LocalStorage, localForage) ->
          localForage.ready().then ->
            # Resolve future (promise argument) according with Promise
            Promise::toFuture = (promise) ->
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
      'curly':                   'vendor/curly/browser'
      'cordjs-zone':             'vendor/zone/zone',
      'dustjs-linkedin':         'vendor/dustjs/dustjs-full'
      'dustjs-helpers':          'vendor/dustjs/dustjs-helpers'
      'eventemitter3':           'vendor/eventemitter3/eventemitter3'
      'jquery':                  'vendor/jquery/jquery'
      'jquery.cookie':           'vendor/jquery/plugins/jquery.cookie'
      'localforage':             'vendor/localforage/localforage'
      'monologue':               'vendor/monologue/monologue'
      'postal':                  'vendor/postal/postal_lite'
      'the-box':                 'vendor/the-box/app'
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

define ->

  services:
    api:
      deps: ['config', 'container', 'cookie', 'request']
      factory: (get, done) ->
        require ['cord!/cord/core/Api'], (Api) ->
          config = get('config')
          api = new Api(get('container'), config.api)
          get('container').injectServices(api).done ->
            api.setupAuthModule().then ->
              done(null, api)

    userAgent:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/UserAgent'], (UserAgent) =>
          userAgent = new UserAgent
          get('container').injectServices(userAgent).done ->
            userAgent.calculate()
            done(null, userAgent)

    modelProxy:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/ModelProxy'], (ModelProxy) =>
          modelProxy = new ModelProxy
          get('container').injectServices(modelProxy).done ->
            done(null, modelProxy)

    redirector:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/router/Redirector'], (Redirector) ->
          redirector = new Redirector()
          get('container').injectServices(redirector).done ->
            done(null, redirector)

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

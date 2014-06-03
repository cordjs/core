define ->

  services:
    api:
      deps: ['config', 'container']
      factory: (get, done) ->
        require ['cord!/cord/core/Api'], (Api) =>
          done null, new Api(get('container'), get('config').api)

    oauth2:
      deps: ['config', 'container']
      factory: (get, done) ->
        require ['cord!/cord/core/OAuth2'], (OAuth2) =>
          done null, new OAuth2(get('container'), get('config').oauth2)

    userAgent:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/UserAgent'], (UserAgent) =>
          userAgent = new UserAgent
          get('container').injectServices(userAgent).done ->
            userAgent.calculate()
            done null, userAgent

    modelProxy:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/ModelProxy'], (ModelProxy) =>
          modelProxy = new ModelProxy
          get('container').injectServices(modelProxy).done ->
            done null, modelProxy

    ':server':
      request:
        deps: ['container']
        factory: (get, done) ->
          require ['cord!/cord/core/request/ServerRequest'], (Request) =>
            done null, new Request(get('container'))

      cookie:
        deps: ['container']
        factory: (get, done) ->
          require ['cord!/cord/core/cookie/ServerCookie'], (Cookie) =>
            done null, new Cookie(get('container'))

      userAgentText:
        deps: ['serverRequest']
        factory: (get, done) ->
          done null, get('serverRequest').headers['user-agent']

    ':browser':
      request:
        deps: ['container']
        factory: (get, done) ->
          require ['cord!/cord/core/request/BrowserRequest'], (Request) =>
            done null, new Request(get('container'))

      cookie:
        deps: ['container']
        factory: (get, done) ->
          require ['cord!/cord/core/cookie/BrowserCookie'], (Cookie) =>
            done null, new Cookie(get('container'))

      userAgentText: (get, done) ->
        done null, navigator.userAgent

      localStorage: (get, done) ->
        require ['cord!cache/localStorage', 'localforage'], (LocalStorage, localForage) ->
          localForage.ready().then ->
            done null, new LocalStorage(localForage)

  routes:
    '/REQUIRESTAT/optimizer':
      widget: '//Optimizer'

  requirejs:
    paths:
      'curly':                   'vendor/curly/browser'
      'dustjs-linkedin':         'vendor/dustjs/dustjs-full'
      'dustjs-helpers':          'vendor/dustjs/dustjs-helpers'
      'jquery':                  'vendor/jquery/jquery'
      'jquery.cookie':           'vendor/jquery/plugins/jquery.cookie'
      'moment':                  'vendor/moment/moment'
      'moment-ru':               'vendor/moment/lang/ru'
      'monologue':               'vendor/postal/monologue'
      'postal':                  'vendor/postal/postal_lite'
      'the-box':                 'vendor/the-box/app'
      'underscore':              'vendor/underscore/underscore'
      'localforage':             'vendor/localforage/localforage'
    shim:
      'curly':
        deps: ['underscore']
        exports: 'curly'
      'dustjs-linkedin':
        exports: 'dust'
      'dustjs-helpers':
        deps: ['dustjs-linkedin']
        exports: 'dust'
      'jquery.cookie':
        deps: ['jquery']
        exports: 'jQuery'
      'underscore':
        exports: '_'
      'moment-ru':
        deps: ['moment']
        exports: 'null'

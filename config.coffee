define [], () ->

  services:
    api:
      deps: ['config']
      factory: (get, done) ->
        require ['cord!/cord/core/Api'], (Api) =>
          done null, new Api(this, get('config').api)

    oauth2:
      deps: ['config']
      factory: (get, done) ->
        require ['cord!/cord/core/OAuth2'], (OAuth2) =>
          done null, new OAuth2(this, get('config').oauth2)

    userAgent:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/UserAgent'], (UserAgent) =>
          userAgent = new UserAgent
          get('container').injectServices(userAgent).done ->
            userAgent.calculate()
            done null, userAgent

    dateUtils:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/utils/DateUtils'], (DateUtils) =>
          dateUtils = new DateUtils(this)
          done null, dateUtils

    modelProxy:
      deps: ['container']
      factory: (get, done) ->
        require ['cord!/cord/core/ModelProxy'], (ModelProxy) =>
          modelProxy = new ModelProxy
          get('container').injectServices(modelProxy).done ->
            done null, modelProxy

    ':server':
      request: (get, done) ->
        require ['cord!/cord/core/request/ServerRequest'], (Request) =>
          done null, new Request(this)

      cookie: (get, done) ->
        require ['cord!/cord/core/cookie/ServerCookie'], (Cookie) =>
          done null, new Cookie(this)

      userAgentText:
        deps: ['serverRequest']
        factory: (get, done) ->
          done null, get('serverRequest').headers['user-agent']

    ':browser':
      request: (get, done) ->
        require ['cord!/cord/core/request/BrowserRequest'], (Request) =>
          done null, new Request(this)

      cookie: (get, done) ->
        require ['cord!/cord/core/cookie/BrowserCookie'], (Cookie) =>
          done null, new Cookie(this)

      userAgentText: (get, done) ->
        done null, navigator.userAgent

      localStorage: (get, done) ->
        require ['cord!cache/localStorage'], (LocalStorage) ->
          done null, LocalStorage

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

baseUrl = '/'

require.config

  baseUrl: baseUrl

  urlArgs: "release=" + global.config.static.release

  paths:
    'postal':           'vendor/postal/postal_lite'
    'monologue':        'vendor/postal/monologue'
    'dustjs-linkedin':  'vendor/dustjs/dustjs-full'
    'dustjs-helpers':   'vendor/dustjs/dustjs-helpers'
    'jquery':           'vendor/jquery/jquery'
    'jquery.ui':        'vendor/jquery/ui/jquery.ui'
    'jquery.ui.selectionMenu': 'vendor/jquery/ui/jquery.ui.selectionMenu'
    'jquery.cookie':    'vendor/jquery/plugins/jquery.cookie'
    'jquery.color':     'vendor/jquery/plugins/jquery.color'
    'jquery.wheel':     'vendor/jquery/plugins/jquery.wheel'
    'jquery.scrollTo':  'vendor/jquery/plugins/jquery.scrollTo'
    'jquery.removeClass': 'vendor/jquery/plugins/jquery.removeClass'
    'curly':            'vendor/curly/browser'
    'underscore':       'vendor/underscore/underscore'
    'requirejs':        'vendor/requirejs/require'
    'the-box':          'vendor/the-box/app'
    'moment':           'vendor/moment/moment'
    'moment-ru':        'vendor/moment/lang/ru'
    'sockjs':           'vendor/sockjs/sockjs'
    'ecomet':           'bundles/megaplan/front/common/utils/Ecomet'

  shim:
    'dustjs-linkedin':
      exports: 'dust'
    'dustjs-helpers':
      deps: ['dustjs-linkedin']
      exports: 'dust'
    'underscore':
      exports: '_'


define [
  'jquery'
  'bundles/cord/core/configPaths'
], ($, configPaths) ->

  require.config configPaths
  require [
    'cord!/cord/core/appManager'
    'cord!WidgetRepo'
    'cord!ServiceContainer'
    'cord!css/browserManager'
    'cord!Console'
  ], (clientSideRouter, WidgetRepo, ServiceContainer, cssManager, _console) ->

    serviceContainer = new ServiceContainer()

    window._console = _console

    ###
      Конфиги
    ###

    serviceContainer.def 'config', ->
      config = global.config
      api:
        protocol: config.api.protocol
        host: window.location.host
        urlPrefix: config.api.urlPrefix
        getUserPasswordCallback: (callback) =>
          backPath = window.location.pathname
          backPath = '/' if backPath.indexOf('user/login') >= 0 or backPath.indexOf('user/logout') >= 0
          clientSideRouter.navigate '/user/login/?back=' + window.location.pathname
      ecomet: config.ecomet
      oauth2:
        clientId: config.oauth2.clientId
        secretKey: config.oauth2.secretKey
        endpoints:
          accessToken: config.oauth2.endpoints.accessToken

    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error) ->
      requirejs ['postal'], (postal) ->
        message = 'Ой! Кажется, нет связи, подождите, может восстановится.'
        postal.publish 'notify.addMessage', {link:'', message: message, details: error.toString(), error:true, timeOut: 50000 }

    serviceContainer.def 'request', (get, done) ->
      requirejs ['cord!/cord/core/request/BrowserRequest'], (Request) ->
        done null, new Request serviceContainer

    serviceContainer.def 'cookie', (get, done) ->
      requirejs ['cord!/cord/core/cookie/BrowserCookie'], (Cookie) ->
        done null, new Cookie serviceContainer

    serviceContainer.def 'oauth2', ['config'], (get, done) ->
      requirejs ['cord!/cord/core/OAuth2'], (OAuth2) ->
        done null, new OAuth2 serviceContainer, get('config').oauth2

    serviceContainer.def 'api', ['config'], (get, done) ->
      requirejs ['cord!/cord/core/Api'], (Api) ->
        done null, new Api serviceContainer, get('config').api

    serviceContainer.def 'user', ['api'], (get, done) ->
      get('api').get 'employee/current/?_extra=user.id', (response) =>
        done null, response

    serviceContainer.def 'inboxRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/inbox//InboxRepo'], (InboxRepo) ->
        done null, new InboxRepo(serviceContainer)

    serviceContainer.def 'discussRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/talks//DiscussRepo'], (DiscussRepo) ->
        done null, new DiscussRepo(serviceContainer)

    serviceContainer.def 'discussFilterRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/talks//DiscussFilterRepo'], (DiscussFilterRepo) ->
        done null, new DiscussFilterRepo(serviceContainer)

    serviceContainer.def 'taskRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/tasks//TaskRepo'], (TaskRepo) ->
        done null, new TaskRepo(serviceContainer)

    serviceContainer.def 'taskFilterRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/tasks//TaskFilterRepo'], (TaskFilterRepo) ->
        done null, new TaskFilterRepo(serviceContainer)

    serviceContainer.def 'taskListRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/tasks//TaskListRepo'], (TaskListRepo) ->
        done null, new TaskListRepo(serviceContainer)

    serviceContainer.def 'staffRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/staff//StaffRepo'], (StaffRepo) ->
        done null, new StaffRepo(serviceContainer)

    serviceContainer.def 'eventRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/todo//EventRepo'], (EventRepo) ->
        done null, new EventRepo(serviceContainer)

    serviceContainer.def 'ecomet', (get, done) ->
      requirejs ['ecomet'], (Ecomet) ->
        done null, new Ecomet(serviceContainer)

    serviceContainer.def 'localStorage', (get, done) ->
      require ['cord!cache/localStorage'], (LocalStorage) ->
        done null, LocalStorage

    ###
    ###

    widgetRepo = new WidgetRepo

    serviceContainer.set 'widgetRepo', widgetRepo
    widgetRepo.setServiceContainer serviceContainer

    clientSideRouter.setWidgetRepo widgetRepo
    $ ->
      cssManager.registerLoadedCssFiles()
      cordcorewidgetinitializerbrowser? widgetRepo

require.config

  baseUrl: '/'

  urlArgs: "release=" + global.config.static.release

  paths:
    'postal':                  'vendor/postal/postal_lite'
    'monologue':               'vendor/postal/monologue'
    'dustjs-linkedin':         'vendor/dustjs/dustjs-full'
    'dustjs-helpers':          'vendor/dustjs/dustjs-helpers'
    'jquery':                  'vendor/jquery/jquery'
    'jquery.ui':               'vendor/jquery/ui/jquery.ui'
    'jquery.ui.selectionMenu': 'vendor/jquery/ui/jquery.ui.selectionMenu'
    'jquery.cookie':           'vendor/jquery/plugins/jquery.cookie'
    'jquery.color':            'vendor/jquery/plugins/jquery.color'
    'jquery.wheel':            'vendor/jquery/plugins/jquery.wheel'
    'jquery.scrollTo':         'vendor/jquery/plugins/jquery.scrollTo'
    'jquery.removeClass':      'vendor/jquery/plugins/jquery.removeClass'
    'jquery.jcrop':            'vendor/jquery/plugins/jcrop/jquery.Jcrop'
    'jquery.transitionEvents': 'vendor/jquery/plugins/transition-events'
    'curly':                   'vendor/curly/browser'
    'underscore':              'vendor/underscore/underscore'
    'requirejs':               'vendor/requirejs/require'
    'the-box':                 'vendor/the-box/app'
    'moment':                  'vendor/moment/moment'
    'moment-ru':               'vendor/moment/lang/ru'
    'sockjs':                  'vendor/sockjs/sockjs'

  shim:
    'dustjs-linkedin':
      exports: 'dust'
    'dustjs-helpers':
      deps: ['dustjs-linkedin']
      exports: 'dust'
    'underscore':
      exports: '_'
    'jquery.ui.selectionMenu':
      deps: ['jquery.ui']


require [
  'bundles/cord/core/requirejs/pathConfig'
  'jquery'
], (pathConfig, $) ->

  require.config(paths: pathConfig)
  require [
    'cord!AppConfigLoader'
    'cord!Console'
    'cord!css/browserManager'
    'cord!router/clientSideRouter'
    'cord!ServiceContainer'
    'cord!WidgetRepo'
  ], (AppConfigLoader, _console, cssManager, clientSideRouter, ServiceContainer, WidgetRepo) ->

    serviceContainer = new ServiceContainer
    serviceContainer.set 'container', serviceContainer

    window._console = _console

    AppConfigLoader.ready().done (appConfig) ->
      clientSideRouter.addRoutes(appConfig.routes)
      for serviceName, info of appConfig.services
        do (info) ->
          serviceContainer.def serviceName, info.deps, (get, done) ->
            info.factory.call(serviceContainer, get, done)

      ###
        Конфиги
      ###

      serviceContainer.def 'config', ->
        config = global.config
        config.api.authenticateUserCallback = ->
          backPath = window.location.pathname
          if not (backPath.indexOf('user/login') >= 0 or backPath.indexOf('user/logout') >= 0)
            clientSideRouter.navigate '/user/login/?back=' + window.location.pathname
          true
        config

    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error) ->
      _console.warn error.toString()


    widgetRepo = new WidgetRepo

    serviceContainer.set('widgetRepo', widgetRepo)
    widgetRepo.setServiceContainer(serviceContainer)

    clientSideRouter.setWidgetRepo(widgetRepo)
    $ ->
      cssManager.registerLoadedCssFiles()
      AppConfigLoader.ready().done -> cordcorewidgetinitializerbrowser?(widgetRepo)

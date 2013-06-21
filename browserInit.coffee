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
    'cord!AppConfigLoader'
    'cord!Console'
    'cord!css/browserManager'
    'cord!router/clientSideRouter'
    'cord!ServiceContainer'
    'cord!WidgetRepo'
  ], (AppConfigLoader, _console, cssManager, clientSideRouter, ServiceContainer, WidgetRepo) ->

    serviceContainer = new ServiceContainer

    window._console = _console

    AppConfigLoader.ready().done (appConfig) ->
      clientSideRouter.addRoutes(appConfig.routes)
      serviceContainer.def(serviceName, info.deps, info.factory) for serviceName, info of appConfig.services

      ###
        Конфиги
      ###

      serviceContainer.def 'config', ->
        config = global.config
        config.api.getUserPasswordCallback = (callback) =>
          backPath = window.location.pathname
          backPath = '/' if backPath.indexOf('user/login') >= 0 or backPath.indexOf('user/logout') >= 0
          clientSideRouter.navigate '/user/login/?back=' + window.location.pathname
        config

    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error) ->
      requirejs ['postal'], (postal) ->
        message = 'Ой! Кажется, нет связи, подождите, может восстановится.'
        postal.publish 'notify.addMessage', {link:'', message: message, details: error.toString(), error:true, timeOut: 50000 }


    widgetRepo = new WidgetRepo

    serviceContainer.set('widgetRepo', widgetRepo)
    widgetRepo.setServiceContainer(serviceContainer)

    clientSideRouter.setWidgetRepo(widgetRepo)
    $ ->
      cssManager.registerLoadedCssFiles()
      cordcorewidgetinitializerbrowser? widgetRepo

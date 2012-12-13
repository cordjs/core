baseUrl = '/'

require.config

  baseUrl: baseUrl

  urlArgs: "uid=" + (new Date()).getTime()

  paths:
    'postal':           'vendor/postal/postal'
    'dustjs-linkedin':  'vendor/dustjs/dustjs-full'
    'jquery':           'vendor/jquery/jquery'
    'jquery.cookie':    'vendor/jquery/plugins/jquery.cookie'
    'curly':            'vendor/curly/browser'
    'underscore':       'vendor/underscore/underscore'
    'requirejs':        'vendor/requirejs/require'
    'the-box':          'vendor/the-box/app'
    'moment':           'vendor/moment/moment'
    'moment-ru':        'vendor/moment/lang/ru'

  shim:
    'dustjs-linkedin':
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
  ], (clientSideRouter, WidgetRepo, ServiceContainer, cssManager) ->

    serviceContainer = new ServiceContainer()

    ###
      Конфиги
    ###

    serviceContainer.def 'config', ->
      api:
        protocol: 'http'
        host: '192.168.63.208:1337'
        urlPrefix: '_restAPI/http://megaplan.megaplan.ru/api/v2/'
        getUserPasswordCallback: (callback) ->
          window.location.href = '/user/login/?back=' + window.location.pathname
      oauth2:
        clientId: 'ce8fcad010ef4d10a337574645d69ac8'
        secretKey: '2168c151f895448e911243f5c6d6cdc6'
        endpoints:
          accessToken: 'http://192.168.63.208:1337/_restAPI/http://megaplan.megaplan.ru/oauth/access_token'

    ###
      Это надо перенести в более кошерное место
    ###

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
      get('api').get 'employee/current/', (response) =>
        done null, response

    ###
    ###

    widgetRepo = new WidgetRepo

    serviceContainer.set 'widgetRepo', widgetRepo
    widgetRepo.setServiceContainer serviceContainer

    clientSideRouter.setWidgetRepo widgetRepo
    clientSideRouter.process()
    $ ->
      cssManager.registerLoadedCssFiles()
      cordcorewidgetinitializerbrowser? widgetRepo

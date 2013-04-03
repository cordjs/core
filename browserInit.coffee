baseUrl = '/'

require.config

  baseUrl: baseUrl

  urlArgs: "uid=" + (new Date()).getTime()

  paths:
    'postal':           'vendor/postal/postal_lite'
    'monologue':        'vendor/postal/monologue'
    'dustjs-linkedin':  'vendor/dustjs/dustjs-full'
    'dustjs-helpers':   'vendor/dustjs/dustjs-helpers'
    'jquery':           'vendor/jquery/jquery'
    'jquery.ui':        'vendor/jquery/ui/jquery-ui'
    'jquery.cookie':    'vendor/jquery/plugins/jquery.cookie'
    'jquery.color':     'vendor/jquery/plugins/jquery.color'
    'jquery.scrollTo':  'vendor/jquery/plugins/jquery.scrollTo'
    'jquery.dotdotdot': 'vendor/jquery/plugins/jquery.dotdotdot'
    'jquery.jeditable': 'vendor/jquery/plugins/jquery.jeditable'
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
  ], (clientSideRouter, WidgetRepo, ServiceContainer, cssManager) ->

    serviceContainer = new ServiceContainer()

    ###
      Конфиги
    ###

    serviceContainer.def 'config', ->
      api:
        protocol: 'http'
        host: window.location.host
        urlPrefix: '_restAPI/http://megaplan.megaplan/api/v2/'
        getUserPasswordCallback: (callback) ->
          window.location.href = '/user/login/?back=' + window.location.pathname
      ecomet:
        host: 'megaplan.megaplan'
        authUri: '/SdfCommon/EcometOauth/auth'
      oauth2:
        clientId: 'ce8fcad010ef4d10a337574645d69ac8'
        secretKey: '2168c151f895448e911243f5c6d6cdc6'
        endpoints:
          accessToken: 'http://' + window.location.host + '/_restAPI/http://megaplan.megaplan/oauth/access_token'

    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error)->
      requirejs ['postal'], (postal)->
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

    serviceContainer.def 'discussRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/talk//DiscussRepo'], (DiscussRepo) ->
        done null, new DiscussRepo(serviceContainer)

    serviceContainer.def 'userStats', ['api'], (get, done) ->
      get('api').get 'userStat/', (response) =>
        done null, response

    serviceContainer.def 'ecomet', (get, done) ->
      requirejs ['ecomet'], (Ecomet) ->
        done null, new Ecomet(serviceContainer)

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

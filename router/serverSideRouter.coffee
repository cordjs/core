define [
  'url'
  'cord!/cord/core/router/Router'
  'cord!WidgetRepo'
  'cord!ServiceContainer'
  'underscore'
], (url, Router, WidgetRepo, ServiceContainer, _) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url, true

      @setPath req.url

      if (route = @matchRoute path.pathname)

        rootWidgetPath = if route.widget? then route.widget else @defWidget
        action = route.action
        params = _.extend path.query, route.params

        serviceContainer = new ServiceContainer()

        ###
          Другого места получить из первых рук запрос-ответ нет
        ###

        serviceContainer.set 'serverRequest', req
        serviceContainer.set 'serverResponse', res

        ###
          Конфиги
        ###

        serviceContainer.set 'config',
          api:
            protocol: 'http'
            host: 'megaplan.hotfix'
            urlPrefix: 'api/v2/'
            getUserPasswordCallback: (callback) ->
              response = serviceContainer.get 'serverResponse'
              response.writeHead 302,
                Location: '/user/login/'
              response.end()
          oauth2:
            clientId: 'CLIENT'
            secretKey: 'SECRET'
            endpoints:
              accessToken: 'http://megaplan.hotfix/oauth/access_token'

        ###
          Это надо перенести в более кошерное место
        ###

        serviceContainer.def 'request', (get, done) ->
          requirejs ['cord!/cord/core/request/ServerRequest'], (Request) ->
            done null, new Request serviceContainer

        serviceContainer.def 'cookie', (get, done) ->
          requirejs ['cord!/cord/core/cookie/ServerCookie'], (Cookie) ->
            done null, new Cookie serviceContainer

        serviceContainer.def 'oauth2', ['config'], (get, done) ->
          requirejs ['cord!/cord/core/OAuth2'], (OAuth2) ->
            done null, new OAuth2 serviceContainer, get('config').oauth2

        serviceContainer.def 'api', ['config'], (get, done) ->
          requirejs ['cord!/cord/core/Api'], (Api) ->
            done null, new Api serviceContainer, get('config').api

        ###
        ###

        widgetRepo = new WidgetRepo

        serviceContainer.set 'widgetRepo', widgetRepo
        widgetRepo.setServiceContainer serviceContainer

        widgetRepo.setRequest req
        widgetRepo.setResponse res
        widgetRepo.createWidget rootWidgetPath, (rootWidget) ->
          rootWidget._isExtended = true
          widgetRepo.setRootWidget rootWidget

          rootWidget.showAction action, params, (err, output) ->
            if err then throw err
            res.writeHead 200, 'Content-Type': 'text/html'
            res.end output
            # todo: may be need some cleanup before?
            widgetRepo = null

        true
      else
        false


  new ServerSideRouter

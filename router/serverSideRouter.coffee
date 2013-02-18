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
            host: 'megaplan.megaplan.ru'
            urlPrefix: 'api/v2/'
            getUserPasswordCallback: (callback) ->
              response = serviceContainer.get 'serverResponse'
              request = serviceContainer.get 'serverRequest'
              response.writeHead 302,
                Location: '/user/login/?back=' + request.url
              response.end()
          oauth2:
            clientId: 'ce8fcad010ef4d10a337574645d69ac8'
            secretKey: '2168c151f895448e911243f5c6d6cdc6'
            endpoints:
              accessToken: 'http://megaplan.megaplan.ru/oauth/access_token'

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

        serviceContainer.def 'user', ['api'], (get, done) ->
          console.log "serviceContainer.def 'user'"
          get('api').get 'employee/current/?_extra=user.id', (response) =>
            done null, response

        serviceContainer.def 'discussRepo', (get, done) ->
          requirejs ['cord-m!/megaplan/front/talk//DiscussRepo'], (DiscussRepo) ->
            done null, new DiscussRepo(serviceContainer)

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

          rootWidget.show params, (err, output) ->
            if err then throw err
            res.writeHead 200, 'Content-Type': 'text/html'
            res.end output
            # todo: may be need some cleanup before?
            widgetRepo = null

        true
      else
        false


  new ServerSideRouter

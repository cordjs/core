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
          userAgent = new UserAgent()
          get('container').injectServices userAgent
          userAgent.calculate()
          done null, userAgent

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

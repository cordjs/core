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

    ':server':
      request: (get, done) ->
        require ['cord!/cord/core/request/ServerRequest'], (Request) =>
          done null, new Request(this)

      cookie: (get, done) ->
        require ['cord!/cord/core/cookie/ServerCookie'], (Cookie) =>
          done null, new Cookie(this)

    ':browser':
      request: (get, done) ->
        require ['cord!/cord/core/request/BrowserRequest'], (Request) =>
          done null, new Request(this)

      cookie: (get, done) ->
        require ['cord!/cord/core/cookie/BrowserCookie'], (Cookie) =>
          done null, new Cookie(this)

      localStorage: (get, done) ->
        require ['cord!cache/localStorage'], (LocalStorage) ->
          done null, LocalStorage

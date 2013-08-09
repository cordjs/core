define [
  'app/application'
  'cord!isBrowser'
  'cord!utils/Future'
  'underscore'
], (application, isBrowser, Future, _) ->

  class AppConfigLoader
    ###
    Application configuration loader
    Purpose of this class is to load and merge all enabled bundles configurations, including routes and service
     definitions for the service container (DI).
    This is static class. Loading starts immediately after it's required anywhere. Usage:
    ```
    require ['cord!AppConfigLoader], (AppConfigLoader) ->
      AppConfigLoader.ready().done (appConfig) ->
        appConfig.routes
        appConfig.services
    ```
    ###

    @_promise: Future.single()


    @ready: ->
      ###
      Returns future with merged configuration which is completed asynchronously when all configs are loaded and merged
      @return Future(Object)
      ###
      @_promise


    @_load: ->
      application.unshift('cord/core') # core is always enabled

      configs = ("cord!/#{ bundle }/config" for i, bundle of application)

      require configs, (args...) ->
        routes = {}
        services = {}

        for config, i in args
          if config.routes?
            for route, params of config.routes
              # expanding widget path to fully-qualified canonical name if short path is given
              if params.widget and params.widget.substr(0, 2) is '//'
                params.widget = "/#{ application[i] }#{ params.widget }"
            # eliminating duplicate routes here
            # todo: may be it should be reported when there are duplicate routes?
            _.extend(routes, config.routes)

          if config.services
            # flatten services configuration (excluding server-only or browser-only configuration)
            srv = _.clone(config.services)
            flatSrv = {}
            if srv[':browser']?
              _.extend(flatSrv, srv[':browser']) if isBrowser
              delete srv[':browser']
            if srv[':server']?
              _.extend(flatSrv, srv[':server']) if not isBrowser
              delete srv[':server']
            _.extend(flatSrv, srv)
            # normalize services configuration
            for name, def of flatSrv
              services[name] =
                if _.isFunction(def)
                  deps: []
                  factory: def
                else
                  deps: def.deps
                  factory: def.factory
                  autoStart: def.autoStart

        AppConfigLoader._promise.resolve
          routes: routes
          services: services

    # start loading immediately on class loading
    @_load()

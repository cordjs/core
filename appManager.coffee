define [
  "app/application"
  "cord!/cord/core/router/#{ ( if window? then 'clientSideRouter' else 'serverSideRouter' ) }"
  "underscore"
  "cord!Console"
], (application, router, _, _console) ->

  configs = ("cord!/#{ bundle }/config" for i, bundle of application)

  require configs, (args...) ->
    routes = {}

    for config, i in args
      for route, params of config.routes
        # expanding widget path to fully-qualified canonical name if short path is given
        if params.widget and params.widget.substr(0, 2) is '//'
          params.widget = "/#{ application[i] }#{ params.widget }"
      # eliminating duplicate routes here
      # todo: may be it should be reported when there are duplicate routes?
      _.extend(routes, config.routes)

    router.addRoutes(routes)

    if window?
      window._console = _console
    else
      GLOBAL._console = _console

  router

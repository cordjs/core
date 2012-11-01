define [
  "app/application"
  "cord!/cord/core/router/#{ ( if window? then 'clientSideRouter' else 'serverSideRouter' ) }"
  "underscore"
], (application, router, _) ->

  bundles = for i, bundle of application
    "cord!/#{ bundle }/config"

  require bundles, () ->
    routes =
      '^\/_restAPI\/(.*)$':
        widget: '/cord/core//RestApi'
        regexp: true

    for bundle, i in arguments
      for route, params of bundle.routes
        if params.widget and params.widget.substr(0, 2) is '//'
          params.widget = "/#{ application[i] }#{ params.widget }"
      _.extend routes, bundle.routes
    router.addRoutes routes

  router

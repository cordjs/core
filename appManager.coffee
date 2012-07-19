define [
  "app/application"
  "cord!/cord/core/router/#{ ( if window? then 'clientSideRouter' else 'serverSideRouter' ) }"
  "underscore"
], (application, router, _) ->

  bundles = for i, bundle of application
    "cord!/#{ bundle }/config"

  require bundles, () ->
    routes =
      '/_restAPI/:restPath':
        widget: '/cord/core/RestApi'
        regex: false
        params:
          someParam: 11

#    _.extend routes, bundle.routes for bundle in arguments
#    router.addRoutes routes
    for bundle, i in arguments
#      bundle.routes.currentBundle = "/#{ application[i] }"
      _.extend routes, bundle.routes
    router.addRoutes routes

  router

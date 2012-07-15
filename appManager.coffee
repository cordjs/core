`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  "app/application"
  "cord!/cord/core/router/#{ ( if window? then 'clientSideRouter' else 'serverSideRouter' ) }"
  "underscore"
], (application, router, _) ->

  require application, () ->
    routes = {};
    _.extend routes, bundle.routes for bundle in arguments
    router.addRoutes routes

  router

`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'ProjectNS/config'
  ( if window? then 'clientSideRouter' else 'serverSideRouter' )
], (config, router) ->

  router.addRoutes config.routes
  router.setRootWidget config.rootWidget if config.rootWidget?

  router

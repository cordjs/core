`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'pathBundles/TestSite/config'
#  ( if window? then './serverSideRouter' else './clientSideRouter' )
  ( if window? then 'clientSideRouter' else 'serverSideRouter' )
], (config, router) ->

#  console.log if window? then './clientSideRouter' else './serverSideRouter'
#  console.log router
  router.addRoutes config.routes

#  console.log( ':::1222::::', router )

  router

#  console.log '_______-----_____', config
#  isNode = ! window?
#  requireFunction = if window? then require else requirejs
#  routerPath = if window? then './clientSideRouter' else './serverSideRouter'

#  requireFunction [routerPath], (router) =>
#    'sdfsdfsdfsdf'
#    router.addRoutes config.routes
#  router.process()
#  require.config paths


#router.addRoutes(require('./public/bundles/TestSite/routes'));
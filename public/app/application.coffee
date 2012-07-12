`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  '../bundles/TestSite/config'
  ( if window? then 'clientSideRouter' else 'serverSideRouter' )
], (config, router) ->
#
#  nameCord = 'cord!Tab/asdasd/asdasdasd'
#  nameParts = nameCord.split('!')
#  console.log '++++___---- ', nameCord.substr(0, 4)
#
#  console.log nameParts.length
#  console.log nameParts
#  console.log nameParts.slice(1).join('!')

  router.addRoutes config.routes

#  require.config paths: 'ProjectNS': config.ProjectNS if config.ProjectNS?


  router

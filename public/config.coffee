require.config

  deps: ['widgetInitializer']

#  baseUrl: '/public'

  urlArgs: "uid=" + (new Date()).getTime()

  paths:
    'dustjs-linkedin': 'vendor/dustjs/dust-amd-adapter',
    'jquery': 'vendor/jquery/jquery-1.7.2.min',
    'underscore': 'vendor/underscore/underscore-amd-adapter',
    'requirejs': 'vendor/requirejs/require',
    'postal': 'vendor/postal/postal'

    #plugins
    'text': 'vendor/requirejs/plugins/text'
    'use': 'vendor/requirejs/plugins/use'

Cord = {}

require [
  'jquery'
  './clientSideRouter'
  './routes'
], ($, router, routes) ->

  Cord.Router = router
  Cord.Router.addRoutes routes
  Cord.Router.process()
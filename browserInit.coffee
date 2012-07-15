require.config

  baseUrl: '/'

  urlArgs: "uid=" + (new Date()).getTime()

  paths:
    'postal':           '/vendor/postal/postal'
    'dustjs-linkedin':  '/vendor/dustjs/dust-amd-adapter'
    'jquery':           '/vendor/jquery/jquery-1.7.2.min'
    'underscore':       '/vendor/underscore/underscore-amd-adapter'
    'requirejs':        '/vendor/requirejs/require'

define [
  'jquery'
  'bundles/cord/core/configPaths'
], ($, configPaths) ->

  require.config configPaths
  require [
    'cord!/cord/core/appManager'
    'cord!/cord/core/widgetInitializer'
  ], (router, widgetInitializer) ->
    router.process()
    $ ->
      cordcorewidgetinitializerbrowser? widgetInitializer


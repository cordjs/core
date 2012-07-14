`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

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
  'bundles/cord/core/config-paths'
], ($, paths) ->

  require.config paths
  require [
    'app/application'
    'cord!/cord/core/widgetInitializer'
  ], ( router, widgetInitializer ) ->
    router.process()
    $ ->
      cordcorewidgetinitializerbrowser? widgetInitializer


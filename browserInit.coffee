baseUrl = '/'

require.config

  baseUrl: baseUrl

  urlArgs: "uid=" + (new Date()).getTime()

  paths:
    'postal':           'vendor/postal/postal'
    'dustjs-linkedin':  'vendor/dustjs/dustjs-full'
    'jquery':           'vendor/jquery/jquery'
    'underscore':       'vendor/underscore/underscore'
    'requirejs':        'vendor/requirejs/require'

  shim:
    'dustjs-linkedin':
      exports: 'dust'
    'underscore':
      exports: '_'


define [
  'jquery'
  'bundles/cord/core/configPaths'
], ($, configPaths) ->

  require.config configPaths
  require [
    'cord!/cord/core/appManager'
    'cord!WidgetRepo'
    'cord!css/browserManager'
  ], (clientSideRouter, WidgetRepo, cssManager) ->
    widgetRepo = new WidgetRepo
    clientSideRouter.setWidgetRepo widgetRepo
    clientSideRouter.process()
    $ ->
      cssManager.registerLoadedCssFiles()
      cordcorewidgetinitializerbrowser? widgetRepo

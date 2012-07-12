require.config

#  deps: ['widgetInitializer']

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

#    'Router': './Router'
#    'Widget': './Widget'
#    'dustLoader': './dustLoader'
#    'Behaviour': './Behaviour'
#    'clientSideRouter': './clientSideRouter'
#
#    # plugins
#    #    'cord': './vendor/requirejs/plugins/cord'
#    'cord-w': './vendor/requirejs/plugins/cord'
#    'cord-path': './vendor/requirejs/plugins/cord-path'
#    'cord-t': './vendor/requirejs/plugins/cord-t'
#
#    #plugins
##    'text': './vendor/requirejs/plugins/text'
##    'use': './vendor/requirejs/plugins/use'
#
#    'pathBundles': './bundles'
#    'ProjectNS': './bundles/TestSite'

require [
  'jquery'
  './app/paths'
#  './app/application'
], ($, paths) ->

  require.config paths
  require [
    'app/application'
  ], ( router ) ->
    router.process()

#  window.require = require

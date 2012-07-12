`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [],  ->

  paths:
    'Router': './Router'
    'Widget': './Widget'
    'dustLoader': './dustLoader'
    'Behaviour': './Behaviour'
    'clientSideRouter': './clientSideRouter'

    # plugins
#    'cord': './vendor/requirejs/plugins/cord'
    'cord-w': './vendor/requirejs/plugins/cord'
    'cord-path': './vendor/requirejs/plugins/cord-path'
    'cord-t': './vendor/requirejs/plugins/cord-t'

    #plugins
    'text': './vendor/requirejs/plugins/text'
    'use': './vendor/requirejs/plugins/use'

    'pathBundles': './bundles'
    'ProjectNS': './bundles/TestSite'

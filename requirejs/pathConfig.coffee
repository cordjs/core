`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], ->
  ###
  Common path aliases. Always included to the paths config for requirejs
  ###

  bundlesDir = 'bundles'
  pluginsDir = bundlesDir + '/cord/core/requirejs/'

  bundles:     bundlesDir
  pathUtils:   pluginsDir + 'pathUtils'

  #plugins
  'text':      'vendor/requirejs/plugins/text'
  'cord':      pluginsDir + 'cord'
  'cord-w':    pluginsDir + 'cord-w'
  'cord-m':    pluginsDir + 'cord-m'
  'cord-t':    pluginsDir + 'cord-t'

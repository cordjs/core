`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [],  ->
  dir = if window? then '' else './'
  class Config
    PUBLIC_PREFIX: 'preved'

    paths:

      'pathBundles':    dir + 'bundles'

      #plugins
      'text':           dir + 'vendor/requirejs/plugins/text'
      'cord-helper':    dir + 'bundles/cord/core/requirejs/cord-helper'
      'cord':           dir + 'bundles/cord/core/requirejs/cord'
      'cord-w':         dir + 'bundles/cord/core/requirejs/cord-w'
      'cord-t':         dir + 'bundles/cord/core/requirejs/cord-t'
      'cord-s':         dir + 'bundles/cord/core/requirejs/cord-s'

  new Config

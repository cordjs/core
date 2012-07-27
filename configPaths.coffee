`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [],  ->
  dir = if window? then '' else './'
  paths:

    'pathBundles':    dir + 'bundles'
    'currentBundle':  ''

    #plugins
    'text':           dir + 'vendor/requirejs/plugins/text'
    'use':            dir + 'vendor/requirejs/plugins/use'
    'cord-helper':    dir + 'bundles/cord/core/requirejs/cord-helper'
    'cord':           dir + 'bundles/cord/core/requirejs/cord'
    'cord-w':         dir + 'bundles/cord/core/requirejs/cord-w'
    'cord-t':         dir + 'bundles/cord/core/requirejs/cord-t'
    'cord-s':         dir + 'bundles/cord/core/requirejs/cord-s'

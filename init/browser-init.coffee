###
Initializes requirejs configuration and then calls cordjs framework initialization.
###

require.config
  baseUrl: '/'
  urlArgs: "release=" + global.config.static.release

  paths:
    'jquery.ui':               'vendor/jquery/ui/jquery.ui'
    'jquery.ui.selectionMenu': 'vendor/jquery/ui/jquery.ui.selectionMenu'
    'jquery.cookie':           'vendor/jquery/plugins/jquery.cookie'
    'jquery.color':            'vendor/jquery/plugins/jquery.color'
    'jquery.wheel':            'vendor/jquery/plugins/jquery.wheel'
    'jquery.scrollTo':         'vendor/jquery/plugins/jquery.scrollTo'
    'jquery.removeClass':      'vendor/jquery/plugins/jquery.removeClass'
    'jquery.jcrop':            'vendor/jquery/plugins/jcrop/jquery.Jcrop'
    'jquery.transitionEvents': 'vendor/jquery/plugins/transition-events'
    'sockjs':                  'vendor/sockjs/sockjs'

  shim:
    'jquery.ui.selectionMenu':
      deps: ['jquery.ui']

require [
  'bundles/cord/core/requirejs/pathConfig'
  'app/application'
], (pathConfig, application) ->
  require.config(paths: pathConfig)

  application.unshift('cord/core') # core is always enabled
  configs = ("cord!/#{ bundle }/config" for bundle in application)

  require configs, (args...) ->
    require.config(config.requirejs) for config in args when config.requirejs
    require ['cord!init/browserInit'], (browserInit) ->
      browserInit()

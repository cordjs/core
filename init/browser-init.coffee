###
Initializes requirejs configuration and then calls cordjs framework initialization.
###

require.config
  baseUrl: if global.config.localFsMode then '' else '/'
  urlArgs: "release=" + global.config.static.release


require [
  'bundles/cord/core/requirejs/pathConfig'
  'app/application'
], (pathConfig, bundles) ->
  require.config(paths: pathConfig)

  bundles.unshift('cord/core') # core is always enabled
  configs = ("cord!/#{ bundle }/config" for bundle in bundles)

  require configs, (args...) ->
    require.config(config.requirejs) for config in args when config.requirejs
    require ['cord!init/browserInit'], (browserInit) ->
      browserInit()

###
Initializes requirejs configuration and then calls cordjs framework initialization.
###

require.config
  baseUrl: if global.config.localFsMode then '' else '/'
  urlArgs: if global.config.localFsMode then '' else "release=" + global.config.static.release

window.CORD_IS_BROWSER = true
window.CORD_PROFILER_ENABLED = global.config.debug.profiler.enable

require [
  'bundles/cord/core/requirejs/pathConfig'
  'app/application'
], (pathConfig, bundles) ->
  require.config(paths: pathConfig)

  bundles.unshift('cord/core') # core is always enabled
  configs = ("cord!/#{ bundle }/config" for bundle in bundles)

  require configs, (args...) ->
    require.config(config.requirejs) for config in args when config.requirejs

    require [
      'asap/raw'
      'cord!init/browserInit'
      if CORD_PROFILER_ENABLED then 'cord!init/profilerInit' else undefined
    ], (asap, browserInit, profilerInit) ->
      require.nextTick = asap
      profilerInit() if CORD_PROFILER_ENABLED
      browserInit.init()

if global.config.debug.livereload
  require ['bundles/cord/core/init/liveReloader'], (liveReloader) ->
    liveReloader.init()

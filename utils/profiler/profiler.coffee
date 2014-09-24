define [
  'cord!utils/profiler/' + if CORD_PROFILER_ENABLED then 'realProfiler' else 'stubProfiler'
], (prof) ->
  ###
  Profiler proxy module. Returns stub profiler (which does nothing) when profiler is disabled.
  ###
  prof

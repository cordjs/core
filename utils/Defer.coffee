define [
  "./#{ if window? and navigator? and document? then 'browser' else 'server' }/Defer"
], (Defer) ->
  ###
  Wrapper for the efficient nextTick (setTimeout(0)) cross-platform implementation.
  Loads implementation for the browser and server (nodejs) from different modules.
  The object has only one public method: nextTick(fn)
  ###

  Defer

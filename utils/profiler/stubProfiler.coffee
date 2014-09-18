define ->
  ###
  Stub implementation of the profiler API which adds almost no performance penalty.
  Injected instead of the real profiler implementation when it is disabled.
  ###
  newRoot: (name, fn) -> fn()
  timer: (name, newRoot, fn) -> if typeof newRoot == 'function' then newRoot() else fn()
  call: (context, fnName, args...) -> context[fnName].apply(context, args)

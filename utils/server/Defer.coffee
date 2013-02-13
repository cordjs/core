define ->

  class Defer

    @nextTick: (fn) ->
      process.nextTick(fn)

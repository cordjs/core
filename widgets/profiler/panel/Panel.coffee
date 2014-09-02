define [
  'cord!Widget'
], (Widget) ->

  class Panel extends Widget

    behaviourClass: false
    cssClass: 'b-sdf-profiler-panel'
    css: true

    @initialCtx:
      timers: []

    @params:
      timers: ':ctx'

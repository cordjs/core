define [
  'cord!Widget'
], (Widget) ->

  class TimerList extends Widget

    behaviourClass: false
    rootTag: 'ul'
    cssClass: 'b-cord-profiler-timer-list'
    css: true

    @initialCtx:
      timers: []
      nextLevel: 0

    @params:
      timers: ':ctx'
      level: (number) ->
        @cssClass += ' level-color-' + number % 6
        @ctx.set nextLevel: number + 1

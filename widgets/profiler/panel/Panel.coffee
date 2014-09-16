define [
  'cord!Widget'
], (Widget) ->

  class Panel extends Widget

    cssClass: 'b-cord-profiler-panel'
    css: true

    @initialCtx:
      timers: []
      highlightInfo: {}

    @params:
      timers: ':ctx'
      highlightInfo: ':ctx'

    @childEvents:
      'timerList actions.highlight-wait-deps': (payload) -> @emit 'actions.highlight-wait-deps', payload


    expandSlowestPath: ->
      @childByName.timerList?.expandSlowestPath()

define [
  'cord!Widget'
], (Widget) ->

  roundTime = (x) -> (parseFloat(x) / 1000).toFixed(3)

  class Panel extends Widget

    cssClass: 'b-cord-profiler-panel'
    css: true

    @initialCtx:
      timers: []
      highlightInfo: {}
      initTime: 0.0
      minimized: true

    @params:
      timers: ':ctx'
      highlightInfo: ':ctx'
      initTime: (time) -> @ctx.set(initTime: roundTime(time))

    @childEvents:
      'timerList actions.highlight-wait-deps': (payload) -> @emit 'actions.highlight-wait-deps', payload


    onShow: ->
      @addDynClass('minimized')


    expandSlowestPath: ->
      @childByName.timerList?.expandSlowestPath()


    toggleFullPanel: (show) ->
      newValue =
        if show?
          not show
        else
          not @ctx.minimized
      @ctx.set minimized: newValue

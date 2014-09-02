define [
  'cord!Widget'
  'cord!utils/Future'
  'underscore'
], (Widget, Future, _) ->

  class Profiler extends Widget
    ###
    Controller widget for the profiler debug panel
    @browser-only
    ###

    behaviourClass: false

    @initialCtx:
      timers: []

    @params:
      serverUid: 'loadServerProfilingData'


    loadServerProfilingData: (serverUid) ->
      ###
      @browser-only
      ###
      Future.require('jquery').then ($) =>
        $.getJSON("/assets/p/#{serverUid}.json").then (data) =>
          newTimers = _.clone(@ctx.timers)
          @_calculateDerivativeMetrics(data)
          newTimers.unshift(data)
          @ctx.set timers: newTimers


    _calculateDerivativeMetrics: (timerData) ->
      ###
      Calculates some derivative metrics from the very minimum of primary metrics of timers came from server
      Mutates incoming timerData struct
      @param Object timerData
      ###
      max = timerData.ownFinishTime = timerData.startTime + timerData.syncTime + (timerData.asyncTime ? 0)
      if timerData.children
        for child in timerData.children
          @_calculateDerivativeMetrics(child)
          max = child.finishTime if child.finishTime > max
      timerData.finishTime = max
      timerData.totalTime = timerData.finishTime - timerData.startTime
      undefined

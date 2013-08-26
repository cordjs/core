define [
  'cord!Widget'
  'fs'
  './CorrelationGroupOptimizer'
  './HeuristicGroupOptimizer'
], (Widget, fs, CorrelationGroupOptimizer, HeuristicGroupOptimizer) ->

  class Optimizer extends Widget

    behaviourClass: false


    onShow: ->
      statFile = 'require-stat.json'
      @ctx.setDeferred 'optimizerMap'
      fs.readFile statFile, (err, data) =>
        stat = if err then {} else JSON.parse(data)
        @ctx.set optimizerMap: JSON.stringify(@generateOptimizationMap(stat), null, 2)


    generateOptimizationMap: (stat) ->
      resultGroups = []

      # grouping by 100% correlation condition
      corrOptimizer = new CorrelationGroupOptimizer
      stat = corrOptimizer.process(stat)

      # heuristic optimization of the previous stage result
      heuristicOptimizer = new HeuristicGroupOptimizer
      stat = heuristicOptimizer.process(stat)

      stat

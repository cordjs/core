define [
  './OptimizerGroup'
], (OptimizerGroup) ->

  class OptimizerGroupRepo
    ###
    Global repository of optimization groups.
    Creates groups and contains key-value list of OptimizationGroup by their IDs.
    ###

    _groups: {}

    createGroup: (groupId, modules) ->
      @_groups[groupId] = new OptimizerGroup(this, groupId, modules)


    getGroup: (groupId) -> @_groups[groupId]



  new OptimizerGroupRepo

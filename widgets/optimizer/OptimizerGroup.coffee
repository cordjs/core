define [], ->

  class OptimizerGroup
    ###
    Simply little abstraction of module optimization group
    ###

    _items: null
    _modules: null
    _subGroups: null


    constructor: (@repo, @id, items) ->
      ###
      @param OptimizerGroupRepo repo group repository (creator)
      @param String id group unique id
      @param Array[String] items list of modules and/or sub-group ids which belongs to this new group
      ###
      @_items = items
      @_modules = []
      @_subGroups = []
      for item in items
        if group = repo.getGroup(item)
          @_subGroups.push(group)
          @_modules = @_modules.concat(group.getModules())
        else
          @_modules.push(item)


    getItems: -> @_items


    getModules: -> @_modules

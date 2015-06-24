define ->

  class WidgetHierarchy
    ###
    Single source of truth for the information about widgets parent/child relationships.
    ###

    _parentToChild: null
    _childToParent: null


    constructor: ->
      @_parentToChild = {}
      @_childToParent = {}


    registerChild: (parent, child) ->
      ###
      Registers relationchip between two widgets.
      If the child widget was attached to another parent then it's removed from the previous parent's children
      @param {Widget} parent - the parent widget
      @param {Widget} child - the child widget
      ###
      if @_childToParent[child.id]
        children = @_parentToChild[@_childToParent[child.id].id]
        children.splice(children.indexOf(child), 1)

      @_parentToChild[parent.id] or= []
      @_parentToChild[parent.id].push(child)
      @_childToParent[child.id] = parent
      return


    unregisterWidget: (widget, rec = false) ->
      ###
      Removes the given widget and all it's children (recursively) from the hierarchy store
      @param {Widget} widget - the removed widget
      @param {boolean} rec - internal use only, flag that designates recursive call of this method
      ###
      id = widget.id
      # remove children
      if @_parentToChild[id]
        @unregisterWidget(child, true)  for child in @_parentToChild[id]
        delete @_parentToChild[id]
      # remove itself
      if @_childToParent[id]
        if not rec
          # for recursive call this is redundant because @_parentToChild[parentId] will be cleaned in the parent call
          children = @_parentToChild[@_childToParent[id].id]
          children.splice(children.indexOf(widget), 1)
        delete @_childToParent[id]
      return


    getChildren: (parent) ->
      ###
      Returns child widgets for the given parent widget
      @param {Widget} parent
      @return {Array.<Widget>}
      ###
      @_parentToChild[parent.id] or []

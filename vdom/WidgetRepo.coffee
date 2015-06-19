define ->

  class WidgetRepo
    ###
    Global repository of all active widgets of the application
    ###

    _widgetsById: null


    constructor: ->
      @_widgetsById = {}


    registerWidget: (widget) ->
      @_widgetsById[widget.id] = widget
      return


    getById: (id) ->
      @_widgetsById[id]

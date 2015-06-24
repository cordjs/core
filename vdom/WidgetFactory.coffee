define [
  'cord!utils/Future'
], (Promise) ->

  class WidgetFactory

    @inject: [
      'container'
      'vdomWidgetRepo'
      'widgetHierarchy'
    ]


    create: (type, props, slotNodes, parentWidget) ->
      ###
      Creates a new widget instance according to the given arguments
      @param {string} type - widget's class type path in cordjs format
      @param {Object.<string, *>} props - the props come from the parent widget
      @param {Array.<VNode>} slotNodes - slot contents to be inserted into the widget
      @param {Widget=} parentWidget - parent widget for the newly created widget
      @return {Promise.<Widget>}
      ###
      bundleSpec = if parentWidget then "@#{ parentWidget.getBundle() }" else ''

      Promise.require("cord-w!#{type}#{bundleSpec}").bind(this).then (WidgetClass) ->
        @container.injectServices(new WidgetClass(props: props, slotNodes: slotNodes))
      .then (widget) ->
        @vdomWidgetRepo.registerWidget(widget)
        @widgetHierarchy.registerChild(parentWidget, widget)  if parentWidget
        widget


    restore: (type, id, props, state, parentId) ->
      ###
      Restores previously created widget transferred from server to browser
      @param {string} type - widget's class type path in cordjs format (only absolute, no context uses)
      @param {string} id - the widget's id (generated on the server)
      @param {Object.<string, *>} props - the props come from the parent widget
      @param {Object.<string, *>} state - serialized widget's state
      @param {string=} parentId - parent widget id, used to restore hierarchy
      @return {Promise.<Widget>}
      ###
      Promise.require("cord-w!#{type}").bind(this).then (WidgetClass) ->
        @container.injectServices(new WidgetClass(id: id, props: props, state: state))
      .then (widget) ->
        @vdomWidgetRepo.registerWidget(widget)
        @widgetHierarchy.registerChild(@vdomWidgetRepo.getById(parentId), widget)  if parentId
        widget

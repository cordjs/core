define [
  'cord!utils/Future'
], (Future) ->

  class WidgetFactory

    create: (type, props, slotNodes, contextBundle) ->
      ###
      Creates a new widget instance according to the given arguments
      @param {string} type - widget's class type path in cordjs format
      @param {Object.<string, *>} props - the props come from the parent widget
      @param {Array.<VNode>} slotNodes - slot contents to be inserted into the widget
      @param {string=} contextBundle - context bundle name to correctly resolve relative type path
      @return {Promise.<Widget>}
      ###
      bundleSpec = if contextBundle then "@#{ contextBundle }" else ''

      Future.require("cord-w!#{path}#{bundleSpec}").then (WidgetClass) =>
        widget = new WidgetClass(props, slotNodes)
        @container.injectServices(widget)

define [
  'cord!Widget'
  'cord-w'
], (Widget, nameResolver) ->

  class Switcher extends Widget

    @initialCtx:
      widgetType: ''
      widgetParams: {}

    @params:
      'widget, widgetParams': (widget, widgetParams) ->
        if @_contextBundle? and widget?
          nameInfo = nameResolver.getFullInfo "#{ widget }@#{ @_contextBundle }"
          widget = nameInfo.canonicalPath

        # If we are going to change underlying widget we should clean it's event handlers before setting new value
        # to the "widgetParams" context var to avoid unnecessary pushing of state change.
        if widget? and @ctx.widgetType? and widget != @ctx.widgetType
          @cleanChildren()
          # also we should empty new widget params if they doesn't set
          widgetParams ?= {}

        @ctx.set
          widgetType: widget
          widgetParams: widgetParams

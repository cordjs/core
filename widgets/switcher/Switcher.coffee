define [
  'cord!Widget'
], (Widget) ->

  class Switcher extends Widget

    _defaultAction: (params, callback) ->

      # If we are going to change underlying widget we should clean it's event handlers before setting new value
      # to the "widgetParams" context var to avoid unnecessary pushing of state change.
      if params.widget? and @ctx.widgetType? and params.widget != @ctx.widgetType
        @cleanChildren()
        # also we should empty new widget params if they doesn't set
        params.widgetParams ?= {}

      @ctx.set
        widgetType: params.widget
        widgetParams: params.widgetParams
      callback()

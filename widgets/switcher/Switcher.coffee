define [
  'cord!Widget'
], (Widget) ->

  class Switcher extends Widget

    _defaultAction: (params, callback) ->
      @ctx.set
        widgetType: params.widget
        widgetParams: params.widgetParams
      callback()

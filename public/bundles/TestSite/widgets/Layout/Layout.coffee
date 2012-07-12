`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'Widget'
], (dust, Widget) ->

  class Layout extends Widget

    path: 'cord-w!//Layout/'

    _defaultAction: (params, callback) ->
      @ctx.setDeferred 'activeTab'
      @ctx.set
        centralTabGroup: Widget.DEFERRED
      setTimeout =>
          @ctx.set
            activeTab: params.activeTabId
            centralTabGroup: true
        , 200

      callback()

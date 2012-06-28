`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../Widget'
], (dust, Widget) ->

  class MainLayout extends Widget

    path: 'mainLayout/'

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


  MainLayout
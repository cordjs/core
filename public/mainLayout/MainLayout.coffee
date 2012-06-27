`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../Widget'
], (dust, Widget) ->

  class MainLayout extends Widget

    path: 'mainLayout/'

    behaviourClass: null

    _defaultAction: (params, callback) ->
      @ctx.set
        activeTab: params.activeTabId
        centralTabGroup: true

      callback()


  MainLayout
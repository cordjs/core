`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../Widget'
], (dust, Widget) ->

  class MainLayout extends Widget

    path: 'mainLayout/'

    _defaultAction: (params, callback) ->
      @ctx.activeTab = 1
      @ctx.centralTabGroup = true
      setTimeout =>
        console.log "timeout worked", params.activeTabId
        @ctx.set
          activeTab: params.activeTabId
          centralTabGroup: true
      , 500

      callback()


  MainLayout
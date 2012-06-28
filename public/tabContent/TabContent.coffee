`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../dustLoader'
  '../Widget'
], (dust, dustLoader, Widget) ->

  class TabContent extends Widget

    path: 'tabContent/'

    _defaultAction: (params, callback) ->
      @ctx.set 'activeTab', params.activeTabId
      callback()


  TabContent
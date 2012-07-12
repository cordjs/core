`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'Widget'
], (dust, Widget) ->

  class TabContent extends Widget

#    path: 'bundles/TestSite/widgets/tabContent/'
    path: 'cord-w!//tabContent/'

    _defaultAction: (params, callback) ->
      @ctx.set 'activeTab', params.activeTabId
      if params.activeTabId == '2'
        @ctx.setDeferred 'buttonNumber'
        setTimeout =>
          @ctx.set
            buttonNumber: Math.floor(Math.random() * 100)
        , 100
      callback()

  TabContent
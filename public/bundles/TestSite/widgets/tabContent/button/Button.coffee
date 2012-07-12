`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  'Widget'
], (dust, Widget) ->

  class Button extends Widget

    cssClass: 'b-button'
    rootTag: 'span'

#    path: 'cord-w!//tabContent/button/'
    path: 'bundles/TestSite/widgets/tabContent/button/'

    _defaultAction: (params, callback) ->
      @ctx.number = params.number ? 1
      callback()


  Button
`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../dustLoader'
  '../Widget'
], (dust, dustLoader, Widget) ->

  class Button extends Widget

    path: 'button/'

    _defaultAction: (params, callback) ->
      @ctx.number = params.number ? 1
      callback()


  Button
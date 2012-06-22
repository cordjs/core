`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../dustLoader'
  'underscore'
  '../Widget'
], (dust, dustLoader, _, Widget) ->

  class Button extends Widget

    path: 'button/'

    _defaultAction: (params, callback) ->
      @ctx.number = params.number ? 1
      callback()

    renderTemplate: (callback) ->
      dustLoader.loadTemplate 'public/button/button.html', =>
        console.log "button template loaded, number = #{ @ctx.number }"
        dust.render 'button', @ctx, callback


  Button
`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'dustjs-linkedin'
  '../Widget'
], (dust, Widget) ->

  class SimpleLayout extends Widget

    path: 'simpleLayout/'

    behaviourClass: false

    _defaultAction: (params, callback) ->
      @ctx.activeTab = params.activeTabId if params.activeTabId?
      callback()


    renderTemplate: (callback) ->
      dust.render 'simpleLayout', @getBaseContext().push(@ctx), callback



  SimpleLayout

define [
  'jquery'
  '../Behaviour'
], ($, Behaviour) ->

  class ButtonBehaviour extends Behaviour

    _setupBindings: ->
      $('#'+@id).click =>
        alert "Button click #{ @view.ctx.number }!"


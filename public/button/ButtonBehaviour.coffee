define [
  'jquery'
  '../Behaviour'
], ($, Behaviour) ->

  class ButtonBehaviour extends Behaviour

    _setupBindings: ->
      $('#'+@id).click =>
        console.log 'button widget', @widget
        alert "Button click #{ @widget.ctx.number }!"


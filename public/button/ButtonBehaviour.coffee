define [
  'jquery'
  '../Behaviour'
], ($, Behaviour) ->

  class ButtonBehaviour extends Behaviour

    _setupBindings: ->
      console.log 'setupButtonBindings', @id
      $('#'+@id).click =>
        alert "Button click #{ @view.ctx.number }!"


define [
  '../Behaviour'
], (Behaviour) ->

  class ButtonBehaviour extends Behaviour

    el: '.b-button'
    cntClick: 0

    events:
      'click .btn': 'clickButton'
      'mousemove .btn': (e) ->
#        console.log 'a'
        @Log.text( "coords #{e.clientX}x#{e.clientY}, context #{ @widget.ctx.number }" )

    constructor: ->
      super
      @Log = @$('span')

    clickButton: ->
      @Log.text( "click #{++@cntClick}, context #{ @widget.ctx.number }" )

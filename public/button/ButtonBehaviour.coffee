define [
  '../Behaviour'
], (Behaviour) ->

  class ButtonBehaviour extends Behaviour
    className: 'initButton'

    el: '.b-button'
    cntClick: 0 if !parseInt(Cord.Router.getURLParameter 'cntClick')

    elements:
      '.log-move': 'logMove'
      '.log-click': 'logClick'

    events:
      'click .btn': 'clickButton'
      'mousemove .btn': (e) ->
#        console.log 'a'
        @logMove.text( "coords #{e.clientX}x#{e.clientY}, context #{ @widget.ctx.number }" )

    clickButton: ->
      @logClick.text( "click #{++@cntClick}, context #{ @widget.ctx.number }" )
      @append '<div>test add </div>'
      Cord.Router.navigate "#{ Cord.Router.getPath() }?cntClick=#{@cntClick}&ctx=#{ @widget.ctx.number }", false

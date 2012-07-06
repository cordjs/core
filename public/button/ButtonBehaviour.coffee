define [
  '../Behaviour'
  '../clientSideRouter'
], (Behaviour, Router) ->

  class ButtonBehaviour extends Behaviour
    className: 'initButton'

    cntClick: 0

    constructor: ->
      super

      i = parseInt( Router.getURLParameter 'cntClick' )
      @cntClick = i if i


    elements:
      '.log-move': 'logMove'
      '.log-click': 'logClick'

    events:
      'click .btn': 'clickButton'
      'mousemove .btn': (e) ->
#        console.log 'a'
        @logMove.text( "coords #{e.clientX}x#{e.clientY}, context #{ @widget.ctx.number }" )

    clickButton: ->
      @logClick.text( "click #{++@cntClick}, context #{ @widget.ctx.number }, path: #{ Router.getPath() }" )
      @append '<div>test add </div>'
      Router.navigate "#{ Router.getPath() }?cntClick=#{@cntClick}&ctx=#{ @widget.ctx.number }", false

define [
  'cord!Behaviour'
], (Behaviour) ->

  class TimerBehaviour extends Behaviour

    @elements:
      '>.e-name': 'timerName' # > is needed due to recursive nature of the widget
      '>.e-time.has-children span': 'totalTime'
      '>.e-timer-desc': 'timerDesc'

    @events:
      'click @totalTime': (evt) ->
        evt.stopPropagation()
        @widget.toggleChildren()

      'click @timerName': (evt) ->
        evt.stopPropagation() # necessary due to recursive nature of the widget
        @widget.toggleDesc()


    @widgetEvents:
      showChildren: (data) ->
        if @widget.childByName.childTimers?
          @$('#'+@widget.childByName.childTimers.ctx.id).toggleClass('hidden', not data.value)
        else
          # if children hasn't been rendered yet, just performing re-render
          @render()

      showDesc: (data) ->
        @timerDesc.toggleClass('hidden', not data.value)

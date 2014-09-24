define [
  'cord!Behaviour'
], (Behaviour) ->

  class TimerBehaviour extends Behaviour

    @elements:
      '>.e-name': 'timerName' # > is needed due to recursive nature of the widget
      '>.e-time': 'totalTimeContainer'
      '>.e-time.has-children span': 'totalTime'
      '>.e-timer-desc': 'timerDesc'
      '>.e-timer-desc .e-wait-deps': 'waitDeps'

    @events:
      'click': (evt) -> evt.stopPropagation() # necessary due to recursive nature of the widget
      'click @totalTime': -> @widget.toggleChildren()
      'click @timerName': -> @widget.toggleDesc()
      'click @waitDeps':  -> @widget.triggerHighlightWaitDeps()


    @widgetEvents:
      highlightType: (data) ->
        @totalTimeContainer.removeClass('wait-deps-highlight-' + data.oldValue) if data.oldValue != 'none'
        @totalTimeContainer.addClass('wait-deps-highlight-' + data.value) if data.value != 'none'

      showChildren: (data) ->
        if @widget.childByName.childTimers
          @$('#'+@widget.childByName.childTimers.ctx.id).toggleClass('hidden', not data.value)
        else
          # if children hasn't been rendered yet, just performing re-render
          @render()

      showDesc: (data) ->
        @timerDesc.toggleClass('hidden', not data.value)


    init: ->
      type = @widget.ctx.highlightType
      @totalTimeContainer.addClass('wait-deps-highlight-' + type) if type != 'none'

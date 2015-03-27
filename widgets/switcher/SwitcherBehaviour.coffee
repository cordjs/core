define [
  'cord!Behaviour'
  'cord!utils/DomHelper'
  'cord!utils/Future'
], (Behaviour, DomHelper, Future) ->

  class SwitcherBehaviour extends Behaviour

    init: ->
      @addSubscription @widget.on('behaviour.switchWidget', @switchWidget)


    switchWidget: (switchInfo) => # fat arrow is mandatory
      ###
      Performs manual switching of the content widget with basic support for hide/show animation via css-classes
      ###
      newWidgetType = switchInfo.widget
      newParams     = switchInfo.params
      oldWidget     = switchInfo.oldWidget
      queuePromise  = switchInfo.queuePromise

      oldWidgetEl = @el.children().first()
      # old widget can prepare for hide animation
      oldWidgetEl.addClass('cord-switcher-hide-start')

      @initChildWidget(newWidgetType, newParams).spread (newWidgetEl, newWidget) =>

        if @widget.ctx.contentWidget == newWidgetType # this check could be redundant but let it be just in case
          @widget.subscribeChildPushBindings newWidget,
            params: 'contentParams'

        animateDelayPromise =
          if oldWidget and (animateDuration = oldWidget.getSwitcherHideAnimateDuration?())
            oldWidgetEl.removeClass('cord-switcher-hide-start').addClass('cord-switcher-hide-finish')
            # giving time to the old widget to perform animation if it wants to
            Future.timeout(animateDuration)
          else
            Future.resolved()

        animateShowDuration = newWidget.getSwitcherHideAnimateDuration?()
        animateDelayPromise.then =>
          oldWidget.drop()  if oldWidget
          oldWidgetEl.remove()
          newWidgetEl.addClass('cord-switcher-show-start')  if animateShowDuration
          DomHelper.append(@el, newWidgetEl)
        .then ->
          if animateShowDuration
            newWidgetEl.removeClass('cord-switcher-show-start').addClass('cord-switcher-show-finish')
            # giving time to the new widget to perform animation if it wants to, before marking the widget as shown
            Future.timeout(animateShowDuration)
          else
            Future.resolved()
        .then ->
          newWidget.markShown()
      .link(queuePromise)

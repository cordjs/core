define [
  'cord!Widget'
  'cord-w'
  'cord!utils/Future'
], (Widget, nameResolver, Future) ->

  class Switcher extends Widget

    # promise to hold processing of swithing to the new widget until the previous switch is complete
    _switchQueuePromise: null
    # this is temporary store for the incoming params to be able to skip all switches besides the latest
    _latestArgs: null

    @initialCtx:
      contentWidget: ''
      contentParams: {}

    @params:
      'widget, widgetParams': (widgetPath, widgetParams) ->
        # @_contextBundle is provided by the core to facilitate context-aware containing widget path resolving
        if @_contextBundle? and widgetPath?
          nameInfo = nameResolver.getFullInfo("#{ widgetPath }@#{ @_contextBundle }")
          widgetPath = nameInfo.canonicalPath

        # first time in browser after server rendering
        @_switchQueuePromise ?= Future.resolved()
        if not @_latestArgs
          @_latestArgs =
            widgetPath: @ctx.contentWidget

        currentSwitchPromise = Future.single("Switcher switch to []")

        @_latestArgs =
          # context of the parent widget will not emit event if the widgetPath is not changed, have to default to previous
          widgetPath: widgetPath or @_latestArgs.widgetPath
          widgetParams: widgetParams
        # local var should match the one in @_latestArgs to compare properly below
        widgetPath or= @_latestArgs.widgetPath

        @_switchQueuePromise.catch (err) ->
          _console.error 'switch queue error report', err  if not err.isCordInternal
        .then @getCallback =>
          # checking if this phase of switching is obsolete and skipping in favour of the newest switch
          if widgetPath == @_latestArgs.widgetPath and widgetParams == @_latestArgs.widgetParams
            if widgetPath and @ctx.contentWidget and widgetPath != @ctx.contentWidget
              # If we are going to change underlying widget we should clean it's event handlers before setting new value
              # to the "contentParams" context var to avoid unnecessary pushing of state change.
              oldWidget = @children[0]
              @unbindChild(oldWidget)  if oldWidget
              # also we should empty new widget params if they doesn't set
              widgetParams or= {}

              @ctx.set
                contentWidget: widgetPath
                contentParams: widgetParams

              # commanding behaviour to perform manual switching process
              # currentSwitchPromise will be resolved there
              @emit 'behaviour.switchWidget',
                oldWidget: oldWidget
                widget: widgetPath
                params: widgetParams
                queuePromise: currentSwitchPromise

            else
              @ctx.set
                contentWidget: widgetPath
                contentParams: widgetParams

              currentSwitchPromise.resolve()
          else
            currentSwitchPromise.resolve()

        @_switchQueuePromise = currentSwitchPromise

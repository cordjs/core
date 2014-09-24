define [
  'cord!Behaviour'
], (Behaviour) ->

  class PanelBehaviour extends Behaviour

    @elements:
      '.e-full-panel': 'fullPanel'
      '.e-init-time': 'initTime'

    @widgetEvents:
      timers: 'render'
      minimized: 'onMinimizedChange'
      initTime: 'onInitTimeChange'

    @events:
      'click .e-expand-slowest': -> @widget.expandSlowestPath()
      'click .e-init-time': -> @widget.toggleFullPanel(true)
      'click .e-hide-link': -> @widget.toggleFullPanel(false)


    onMinimizedChange: (data) ->
      @toggleClass('minimized', data.value)
      @render() if @fullPanel.length == 0 and not data.value


    onInitTimeChange: (data) ->
      @initTime.html(data.value)

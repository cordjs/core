define [
  'jquery'
  'Behaviour'
  'clientSideRouter'
], ($, Behaviour, router) ->

  class LayoutBehaviour extends Behaviour

    widgetEvents:
      'activeTab': (data) ->
        $('.nav-tabs .active').removeClass('active')
        $('#tab'+data.value).addClass('active')

define [
  'jquery'
  '../Behaviour'
  '../clientSideRouter'
], ($, Behaviour, router) ->

  class MainLayoutBehaviour extends Behaviour

    widgetEvents:
      'activeTab': (data) ->
        $('.nav-tabs .active').removeClass('active')
        $('#tab'+data.value).addClass('active')

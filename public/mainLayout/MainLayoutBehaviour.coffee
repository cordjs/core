define [
  'jquery'
  '../Behaviour'
  '../clientSideRouter'
], ($, Behaviour, router) ->

  class MainLayoutBehaviour extends Behaviour

    constructor: (widget) ->
      @widgetEvents =
        'activeTab': (data) ->
          $('.nav-tabs .active').removeClass('active')
          $('#tab'+data.value).addClass('active')

      super widget

    _setupBindings: ->
      $(document).on "click", "a:not([data-bypass])", (evt) ->
        href = $(@).prop 'href'
        root = location.protocol + '//' + location.host

        if href and href.slice(0, root.length) == root and href.indexOf("javascript:") != 0
          evt.preventDefault()
          router.navigate href.slice(root.length), true
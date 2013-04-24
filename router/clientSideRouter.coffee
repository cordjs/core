define [
  'jquery'
  'postal'
  'cord!/cord/core/router/Router'
], ($, postal, Router) ->

  hashStrip = /^#*/

  class ClientSideRouter extends Router

    options:
      trigger: true
      history: true
      shim: false

    historySupport: window.history?.pushState?

    widgetRepo: null

    constructor:(options = {}) ->
      super

      @options = $.extend({}, @options, options)

      if (@options.history)
        @history = @historySupport && @options.history

      #save current path
      path = window.location.pathname
      if path.substr(0,1) isnt '/'
        path = '/' + path

      @setPath path

      return if @options.shim

#      @change()

      @initNavigate()

    setWidgetRepo: (widgetRepo) ->
      ###
      Injects widget repository from from browserInit script
      ###
      @widgetRepo = widgetRepo

    process: ->
      postal.subscribe
        topic: 'router.process'
        callback: (route) =>
          widgetPath = if route.widget? then route.widget else @defWidget
          params = route.params

          if @widgetRepo.rootWidget?
            @widgetRepo.injectWidget widgetPath, params
          else
            throw "root widget is undefined!"

      postal.subscribe
        topic: 'router.navigate'
        callback: (args...) =>
          @navigate args...


    matchRoute: (path, options) ->
      for route in @routes
        if route.match(path, options)
          postal.publish 'router.process', route
          return route

    navigate: (args...) ->
      options = {}

      lastArg = args[args.length - 1]
      if typeof lastArg is 'object'
        options = args.pop()
      else if typeof lastArg is 'boolean'
        options.trigger = args.pop()

      options = $.extend({}, @options, options)

      path = args.join('/')
      return if @path is path
      @path = path

      #@trigger('navigate', @path)

      @matchRoute(@path, options) if options.trigger

      return if options.shim

      if @history
        history.pushState(
          {},
          document.title,
          @path
        )
      else
        window.location.hash = @path

    initNavigate: ->
      if @history
        $(window).bind('popstate', => @change())
      else
        $(window).bind('hashchange', => @change())

      route = @
      $(document).on "click", "a:not([data-bypass])", (evt) ->
        href = $(this).prop 'href'
        root = location.protocol + '//' + location.host

        if href and href.slice(0, root.length) == root and href.indexOf("javascript:") != 0
          evt.preventDefault()
          route.navigate href.slice(root.length), true

    change: ->
      path = if @getFragment() isnt '' then @getFragment() else @getPath()

      return if path is @path
      @path = path
      @matchRoute(@path)

    getPath: ->
      path = window.location.pathname
      if path.substr(0,1) isnt '/'
        path = '/' + path
      path

    getHash: -> window.location.hash

    getFragment: -> @getHash().replace(hashStrip, '')

    getHost: ->
      (document.location + '').replace(@getPath() + @getHash(), '')

    getURLParameter: (name) ->
      (RegExp(name + '=' + '(.+?)(&|$)').exec(location.search)||[null,null])[1]


  new ClientSideRouter

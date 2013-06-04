define [
  './Router'
  'cord!PageTransition'
  'jquery'
  'postal'
], (Router, PageTransition, $, postal) ->

  class ClientSideRouter extends Router

    options:
      trigger: true
      history: true
      shim: false

    historySupport: window.history?.pushState?

    widgetRepo: null


    constructor: (options = {}) ->
      super

      @options = $.extend({}, @options, options)

      if (@options.history)
        @history = @historySupport && @options.history

      # save current path
      @currentPath = @getActualPath()

      @_initHistoryNavigate() if @history and not @options.shim


    setWidgetRepo: (widgetRepo) ->
      ###
      Injects widget repository from from browserInit script
      ###
      @widgetRepo = widgetRepo


    process: (newPath) ->
      ###
      Initiates client-side page transition to the given new path.
      @param String newPath path and query-string part of the new url
      @return Boolean true if there was a matching route and the path was actually processed
      ###
      if (routeInfo = @matchRoute(newPath))
        postal.publish('router.process', routeInfo)

        @widgetRepo.transitPage(routeInfo.route.widget, routeInfo.params, new PageTransition(@currentPath, newPath))
        @currentPath = newPath
        true
      else
        false


    navigate: (args...) ->
      ###
      Initiates url changing and related client-side page transition.
      @param (multiple)String path path parts which will be concatenated to form target path
      @param (optional)Boolean|Object options if last argument is boolean, than it's treated as options.trigger
                                              if last argument is Object, than it's treated as options
      ###
      console.clear()
      options = {}
      lastArg = args[args.length - 1]
      if typeof lastArg is 'object'
        options = args.pop()
      else if typeof lastArg is 'boolean'
        options.trigger = args.pop()

      newPath = args.join('/')
      if newPath.substr(0, 1) isnt '/'
        newPath = '/' + newPath
      return if @currentPath == newPath

      if @history
        options = $.extend({}, @options, options)

        @process(newPath) if options.trigger

        history.pushState({}, document.title, @currentPath) if not options.shim
      else
        window.location.href = newPath


    _initHistoryNavigate: ->
      ###
      Setups client-side navigating event handlers.
      ###
      $(window).bind 'popstate', =>
        newPath = @getActualPath()
        @process(newPath) unless newPath == @currentPath

      self = this
      $(document).on 'click', 'a:not([data-bypass])', (evt) ->
        href = $(this).prop('href')
        root = location.protocol + '//' + location.host

        if href and href.slice(0, root.length) == root and href.indexOf("javascript:") != 0
          evt.preventDefault()
          self.navigate href.slice(root.length), true


    getActualPath: ->
      ###
      Extracts current actual path from the window.location
      @return String
      ###
      path = window.location.pathname
      if path.substr(0, 1) isnt '/'
        path = '/' + path
      path


    getHash: -> window.location.hash


    getHost: ->
      (document.location + '').replace(@getActualPath() + @getHash(), '')


    getURLParameter: (name) ->
      (RegExp(name + '=' + '(.+?)(&|$)').exec(location.search)||[null,null])[1]



  new ClientSideRouter

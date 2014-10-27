define [
  './Router'
  'cord!PageTransition'
  'jquery'
  'postal'
], (Router, PageTransition, $, postal) ->

  # detecting private settings from configuration and environment
  # should
  historySupport = window.history?.pushState? and not global.config.localFsMode


  class ClientSideRouter extends Router

    widgetRepo: null


    constructor: ->
      super

      @_noPageReload = historySupport or global.config.localFsMode

      # save current path
      @_currentPath = @getActualPath()

      @_initHistoryNavigate() if historySupport
      @_initLinkClickHook() if @_noPageReload


    setWidgetRepo: (widgetRepo) ->
      ###
      Injects widget repository from from browserInit script
      ###
      @widgetRepo = widgetRepo


    process: (newPath, fallback = false) ->
      ###
      Initiates client-side page transition to the given new path.
      @param String newPath path and query-string part of the new url
      @return Boolean true if there was a matching route and the path was actually processed
      ###
      if (routeInfo = if not fallback then @matchRoute(newPath) else @matchFallbackRoute(newPath))
        postal.publish('router.process', routeInfo)

        query = @parseGetParameters(newPath)
        _.extend(routeInfo.params, query)

        if routeInfo.route.widget?
          @_lastTransitionPromise = @widgetRepo.smartTransitPage(
            routeInfo.route.widget, routeInfo.params, new PageTransition(@_currentPath, newPath)
          )
          @_currentPath = newPath
          true
        else
          false
      else
        false


    navigate: (newPath) ->
      ###
      Initiates url changing and related client-side page transition.
      @param {String} newPath path to navigate to
      @return {Future[undefined]} resolved when page transition is completed
      ###
      _console.clear() if global.config.console.clear

      newPath = '/' + newPath if newPath.charAt(0) != '/'
      return if @_currentPath == newPath

      if window.systemPageRefresh != undefined and window.systemPageRefresh == true
        postal.publish 'mp2.was.updated'
        window.location.replace(newPath)
        return

      if @_noPageReload
        if @process(newPath)
          history.pushState({}, document.title, @_currentPath) if historySupport
          @_lastTransitionPromise.then =>
            # defining navigation completion as when the new root widget is shown in DOM
            @widgetRepo.getRootWidget().shown()
        else
          Future.rejected(new Error("There is no matching route for the url '#{newPath}'"))
      else
        window.location.href = newPath
        # the page will be reloaded so returning uncompleted promise
        Future.single()


    redirect: (newPath) ->
      ###
      Interrupts current active page transition (if any) and navigates the application to the given path.
      The promise of the interrupted transition is linked to the new transition so it'll be completed when the new
       transition is completed. This is helpful to correctly detect the transition completion in case when
       authentication redirect is performed during navigation to the page.
      @param {String} newPath
      @return {Future[undefined]}
      ###
      activeTransitionPromise = @widgetRepo.getActiveTransition()
      @widgetRepo.resetSmartTransition()
      newTransition = @navigate(newPath)
      if activeTransitionPromise and not activeTransitionPromise.completed()
        activeTransitionPromise.when(newTransition)
      newTransition


    _initHistoryNavigate: ->
      ###
      Setups client-side navigating history event handler.
      ###
      $(window).bind 'popstate', =>
        newPath = @getActualPath()
        @process(newPath) if newPath != @_currentPath


    _initLinkClickHook: ->
      ###
      Setups client-side navigating link click event handler.
      ###
      self = this

      # Read more: http://perfectionkills.com/detecting-event-support-without-browser-sniffing/
      clickEventType = if 'ontouchstop' of document.documentElement then 'touchstop' else 'click'
      $(document).on clickEventType, 'a:not([data-bypass],[target="_blank"])', (event) ->
        # Default behaviour for anchors if any modification key pressed
        return if event.metaKey or event.ctrlKey or event.altKey or event.shiftKey

        href = $(this).prop('href')
        root = location.protocol + '//' + location.host

        if href and href.slice(0, root.length) == root and href.indexOf("javascript:") != 0
          event.preventDefault()
          self.navigate(href.slice(root.length))


    getActualPath: ->
      ###
      Extracts current actual path from the window.location
      @return String
      ###
      path = window.location.pathname
      path = '/' + path if path.charAt(0) != '/'
      path


    getHash: -> window.location.hash


    getHost: ->
      (document.location + '').replace(@getActualPath() + @getHash(), '')


    getURLParameter: (name) ->
      (RegExp(name + '=' + '(.+?)(&|$)').exec(location.search)||[null,null])[1]


    parseGetParameters: (path) ->
      params = {}

      questionPos = path.indexOf('?')
      if questionPos != -1
        queryString = path.substring(questionPos + 1)
        queries = queryString.split('&')
        for paramStr in queries
          tmp = paramStr.split('=')
          params[decodeURIComponent(tmp[0])] = decodeURIComponent(tmp[1])
      params


    goBack: ->
      history.back() if @_noPageReload


  new ClientSideRouter

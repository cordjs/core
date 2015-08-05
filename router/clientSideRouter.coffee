define [
  './Router'
  'cord!errors'
  'cord!PageTransition'
  'cord!utils/Future'
  'jquery'
  'postal'
], (Router, errors, PageTransition, Future, $, postal) ->

  # detecting private settings from configuration and environment
  # should
  historySupport = window.history?.pushState? and not global.config.localFsMode


  class ClientSideRouter extends Router

    widgetRepo: null


    constructor: ->
      super

      @_noPageReload = historySupport or global.config?.localFsMode

      # save current path
      @_currentPath = if global.config?.localFsMode then '/' else @getActualPath()

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
          checkAuthPromise =
            if routeInfo.route.requireAuth and _.isFunction(@_authCheckCallback)
              Future.try => @_authCheckCallback()
            else
              Future.resolved(true)
          @_lastTransitionPromise = checkAuthPromise.then (authOk) =>
            if authOk
              @widgetRepo.smartTransitPage(
                routeInfo.route.widget, routeInfo.params, new PageTransition(@_currentPath, newPath)
              )
            else
              Future.rejected(new errors.AuthError("Required auth check not passed for the route #{routeInfo.route}"))
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
      return Future.resolved() if @_currentPath == newPath

      if window.systemPageRefresh != undefined and window.systemPageRefresh == true
        postal.publish 'mp2.was.updated'
        window.location.replace(newPath)
        return Future.resolved()

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
        # transition timeout can reject the promise before here, so need to be checked
        newTransition
          .then (res)  -> activeTransitionPromise.resolve(res) if not activeTransitionPromise.completed()
          .catch (err) -> activeTransitionPromise.reject(err)  if not activeTransitionPromise.completed()
      newTransition


    _initHistoryNavigate: ->
      ###
      Setups client-side navigating history event handler.
      ###
      window.addEventListener 'popstate', =>
        newPath = @getActualPath()
        @process(newPath) if newPath != @_currentPath


    _initLinkClickHook: ->
      ###
      Setups client-side navigating link click event handler.
      ###
      self = this

      # Read more: http://perfectionkills.com/detecting-event-support-without-browser-sniffing/
      clickEventType = if 'ontouchstop' of document.documentElement then 'touchstop' else 'click'
      $(document).on clickEventType, 'a:not([data-bypass],[target="_blank"],[target="_system"])', (event) ->
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
      if global.config?.localFsMode
        # in local environment window.location doesn't make sence
        if (pos = @_currentPath.indexOf('?')) > -1
          @_currentPath.slice(0, pos)
        else
          @_currentPath
      else
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

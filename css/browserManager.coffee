define [
  'cord!utils/Defer'
  'cord!utils/Future'
  'jquery'
  'underscore'
], (Defer, Future, $, _) ->

  # helpers
  doc = document
  head = doc.head || doc.getElementsByTagName('head')[0]
  a = doc.createElement('a')

  baseUrl = if global.config?.localFsMode then '' else '/'

  normalizePath = (path) ->
    ###
    Cuts query params and leading slash from the css path
    ###
    start = if path.charAt(0) == '/' then 1 else 0
    idx = path.indexOf('?')
    end = if idx == -1 then undefined else idx
    path.substr(start, end)


  isLoaded = (url) ->
    # Get absolute url by assigning to a link and reading it back below
    a.href = url

    for i, info of doc.styleSheets
      if info.href == a.href
        return true
    false


  isSafari5 = ->
    !!navigator.userAgent.match(' Safari/') &&
      !navigator.userAgent.match(' Chrom') &&
      !!navigator.userAgent.match(' Version/5.')


  isWebkitNoOnloadSupport = ->
    # Webkit: 535.23 and above supports onload on link tags.
    [supportedMajor, supportedMinor] = [535, 23]
    if (match = navigator.userAgent.match(/\ AppleWebKit\/(\d+)\.(\d+)/))
      match.shift()
      [major, minor] = [+match[0], +match[1]]
      major < supportedMajor || major == supportedMajor && minor < supportedMinor


  isLinkOnLoadSupport = ->
    ###
    Is current browser supports link.onload method
    ###
    not isSafari5() and not isWebkitNoOnloadSupport() and _.has(document.createElement('link'), 'onload')


  class BrowserManager
    ###
    @browser-only
    ###

    _loadedFiles: null
    _loadingOrder: null # used by the optimizer to preserve ordering when groupping
    _nativeLoad: null
    _nativeLoadPromise: null

    _groupToCss: null
    _cssToGroup: null


    constructor: ->
      @_loadedFiles = {}
      @_loadingOrder = []
      @_cssToGroup = {}
      # Below code tested on Android 4.3 (no link.onload support) and Chrome 37.0.2062.120 (link.onload supported)
      if isLinkOnLoadSupport()
        # use css loading via native link.onload
        @_loadCss = @_loadLink
      else
        # use css loading via img.onload hack
        @_loadCss = @_loadImg


    load: (cssPath) ->
      ###
      Adds css-file to the page if it is not already loaded
      @return Future
      ###
      normPath = normalizePath(cssPath)
      if not @_loadedFiles[normPath]?
        if not @_cssToGroup[normPath]
          @_loadedFiles[normPath] = @_loadCss("#{ baseUrl }#{ normPath }?release=#{ global.config.static.release }")
          @_loadedFiles[normPath].then =>
            # memory optimization
            @_loadedFiles[normPath] = Future.resolved()
          @_loadingOrder.push(normPath)
        else
          groupId = @_cssToGroup[normPath]
          loadPromise = @_loadCss("#{baseUrl}assets/z/#{groupId}.css")
          @_loadedFiles[css] = loadPromise for css in @_groupToCss[groupId]
          loadPromise.then =>
            # memory optimization
            @_loadedFiles[css] = Future.resolved() for css in @_groupToCss[groupId]

      else if @_loadedFiles[normPath] == true
        @_loadedFiles[normPath] = Future.resolved()
      @_loadedFiles[normPath]


    registerLoadedCssFiles: ->
      ###
      Scans page's link tags and registers already loaded css files in manager.
      This is needed to prevent double loading of the files when css files are on demand by client-side code.
      ###
      that = this
      $("head > link[rel='stylesheet']").each -> # cannot use fat-arrow here!!
        normPath = normalizePath($(this).attr('href'))
        if result = normPath.match /assets\/z\/([^\.]+)\.css$/
          groupId = result[1]
          that._loadedFiles[css] = true for css in that._groupToCss[groupId]
        else
          # 'true' is optimization, the completed future will be lazy-created in load() method if needed
          that._loadedFiles[normPath] = true
          that._loadingOrder.push(normPath)


    setGroupLoadingMap: (groupMap) ->
      ###
      Used in optimized browser-init script to setup css-group optimization rules on the browser-side.
      @param Map[String, Array[String]] groupMap
      ###
      @_groupToCss = groupMap
      @_cssToGroup = {}
      for groupId, urls of groupMap
        for css in urls
          @_cssToGroup[css] = groupId


    _loadLink: (url) ->
      ###
      Load using the browsers built-in load event on link tags
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
      promise = Future.single("browserManager::_loadLink(#{url})")
      link = @_createLink(url);

      link.onload = ->
        promise.resolve()
        link.onload = null

      head.appendChild(link)

      promise


    _loadScript: (url) ->
      ###
      Insert a script tag and use it's onload & onerror to know when
       the CSS is loaded, this will unfortunately also fire on other
       errors (file not found, network problems)
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
      promise = Future.single("browserManager::_loadScript(#{url})")
      link = @_createLink(url)
      script = doc.createElement('script');

      head.appendChild(link);

      script.onload = script.onerror = ->
        head.removeChild(script)

        # In Safari the stylesheet might not yet be applied, when
        # the script is loaded so we poll document.styleSheets for it
        checkLoaded = ->
          if isLoaded(url)
            promise.resolve()
          else
            setTimeout(checkLoaded, 25)

        checkLoaded()

      script.src = url
      head.appendChild(script)

      promise


    _loadImg: (url) ->
      ###
      Insert a img tag and use it's onload & onerror to know when
       the CSS is loaded, this will unfortunately also fire on other
       errors (file not found, network problems)
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
      promise = Future.single("browserManager::_loadImg(#{url})")
      img = doc.createElement('img');

      head.appendChild(@_createLink(url));

      img.onerror = ->
        # In Safari the stylesheet might not yet be applied, when
        # the script is loaded so we poll document.styleSheets for it
        checkLoaded = ->
          if isLoaded(url)
            promise.resolve()
          else
            setTimeout(checkLoaded, 25)

        checkLoaded()

      img.src = url

      promise


    _createLink: (url) ->
      link = doc.createElement('link')

      link.rel = "stylesheet"
      link.type = "text/css"
      link.href = url

      link



  new BrowserManager

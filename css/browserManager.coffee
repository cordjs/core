define [
  'cord!utils/Defer'
  'cord!utils/Future'
  'jquery'
], (Defer, Future, $) ->

  # helpers
  doc = document
  head = doc.head || doc.getElementsByTagName('head')[0]
  a = doc.createElement('a')

  normalizePath = (path) ->
    ###
    Cuts query params from path
    ###
    idx = path.lastIndexOf('?')
    if idx == -1
      path
    else
      path.substr(0, idx)

  isLoaded = (url) ->
    # Get absolute url by assigning to a link and reading it back below
    a.href = url

    for i, info of doc.styleSheets
      if info.href == a.href
        return true
    false


  class BrowserManager
    ###
    @browser-only
    ###

    _loadedFiles: null
    _loadingOrder: null
    _nativeLoad: null
    _nativeLoadPromise: null

    constructor: ->
      @_loadedFiles = {}
      @_loadingOrder = []

    load: (cssPath) ->
      ###
      Adds css-file to the page if it is not already loaded
      @return Future
      ###
      normPath = normalizePath(cssPath)
      if not @_loadedFiles[normPath]?
        @_loadedFiles[normPath] = @_loadLink(cssPath)
        @_loadingOrder.push(normPath)
      else if @_loadedFiles[normPath] == true
        @_loadedFiles[normPath] = Future.resolved()
      @_loadedFiles[normPath]


    registerLoadedCssFiles: ->
      ###
      Scans page's link tags and registers already loaded css files in manager.
      This is needed to prevent double loading of the files when css files are on demand by client-side code.
      ###
      tmpLoaded = @_loadedFiles
      $("head > link[rel='stylesheet']").each ->
        normPath = normalizePath($(this).attr('href'))
        # 'true' is optimization, the completed future will be lazy-created in load() method if needed
        tmpLoaded[normPath] = true
        @_loadingOrder.push(normPath)


    _loadLink: (url) ->
      ###
      Load using the browsers built-in load event on link tags
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
      promise = Future.single('browserManager::_loadLink')
      link = @_createLink(url);

      link.onload = ->
        promise.resolve()
        link.onload = null

      head.appendChild(link)

      promise


    _loadScript: (url, promise) ->
      ###
      Insert a script tag and use it's onload & onerror to know when
       the CSS is loaded, this will unfortunately also fire on other
       errors (file not found, network problems)
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
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


    _loadImg: (url, promise) ->
      ###
      Insert a img tag and use it's onload & onerror to know when
       the CSS is loaded, this will unfortunately also fire on other
       errors (file not found, network problems)
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
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


    _createLink: (url) ->
      link = doc.createElement('link')

      link.rel = "stylesheet"
      link.type = "text/css"
      link.href = url

      link



  new BrowserManager

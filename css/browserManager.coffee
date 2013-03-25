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
    _nativeLoad: null
    _nativeLoadPromise: null

    constructor: ->
      @_loadedFiles = {}

    load: (cssPath) ->
      ###
      Adds css-file to the page if it is not already loaded
      @return Future
      ###
      normPath = normalizePath(cssPath)
      if not @_loadedFiles[normPath]?
        @_loadedFiles[normPath] = new Future(1)
        @_checkNativeLoad().done (nativeLoad) =>
          if nativeLoad
            @_loadLink(cssPath, @_loadedFiles[normPath])
          else
            @_loadImg(cssPath, @_loadedFiles[normPath])
      else if @_loadedFiles[normPath] == true
        @_loadedFiles[normPath] = new Future
      @_loadedFiles[normPath]


    registerLoadedCssFiles: ->
      ###
      Scans page's link tags and registers already loaded css files in manager.
      This is needed to prevent double loading of the files when css files are on demand by client-side code.
      ###
      tmpLoaded = @_loadedFiles
      $("head > link[rel='stylesheet']").each ->
        # 'true' is optimization, the completed future will be lazy-created in load() method if needed
        tmpLoaded[normalizePath($(this).attr('href'))] = true

      # starting native load feature detection async process immediately so we'll not have to wait later
      @_nativeLoad = doc.createElement('link').onload == null ? null : false
      @_checkNativeLoad()


    _checkNativeLoad: ->
      ###
      Async process of browser feature detection about link.onload capability.
      @return Future(Boolean)
      ###
      if not @_nativeLoadPromise?
        @_nativeLoadPromise = new Future(1)
        if @_nativeLoad != false
          # Create a link element with a data url, it would fire a load event immediately
          link = @_createLink('data:text/css,')

          link.onload = =>
            # Native link load event works
            @_nativeLoad = true
            @_nativeLoadPromise.resolve(true)

          head.appendChild(link)

          # Schedule function in event loop, this will execute after a potential execution of the link onload
          Defer.nextTick =>
            head.removeChild(link)
            if @_nativeLoad != true
              # Native link load event is broken
              @_nativeLoad = false
              @_nativeLoadPromise.resolve(false)
        else
          @_nativeLoadPromise.resolve(false)

      @_nativeLoadPromise


    _loadLink: (url, promise) ->
      ###
      Load using the browsers built-in load event on link tags
      @param String url css-file url to load
      @param Future promise future to resolve when the CSS is loaded
      ###
      link = @_createLink(url);

      link.onload = ->
        promise.resolve()
        link.onload = null

      head.appendChild(link)


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

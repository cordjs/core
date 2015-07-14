define [
  'cord!templateLoader'
  'cord!utils/Future'
  'dustjs-helpers'
], (templateLoader, Future, dust) ->

  class TimeoutStubHelper
    ###
    This is helper class to prevent code duplication and extract some code from the huge Widget class
     related to the widget timeout-stub processing.
    ###

    @replaceStub: (html, widget, domInfo) ->
      ###
      Correctly replaces widget's timeout stub with the given html and browser-initializes the widget
       at the right moment according to the given context DOM info
      @param String hmtl widget's rendered template
      @param Widget widget the inserted widget
      @param DomInfo domInfo special helper object holding futures about context DOM creating and inserting
      @return Future[jQuery] new DOM root to be used by the enclosed widgets
      ###
      Future.require('jquery', 'cord!utils/DomHelper').spread ($, DomHelper) ->
        $newRoot = $(widget.renderRootTag(html))
        # _delayedRender flag MUST be unset here (not before) to avoid interference of another browserInit during
        #  async Future.require() above
        widget.unsetDelayedRender()
        # we should browser-init and mark-shown not only rendered widget, but also it's placeholders actual content widgets
        # but we shouldn't touch delayed widgets with their own timeout stub settings, they will care about initialization theirself
        affectedWidgets = [widget].concat(widget.getNonDelayedPlaceholderWidgetsDeep())
        browserInitPromises = (w.browserInit($newRoot) for w in affectedWidgets)

        Future.all [
          domInfo.domRootCreated()
          Future.all(browserInitPromises)
        ]
        .spread ($contextRoot) ->
          oldElement = $('#'+widget.ctx.id, $contextRoot)
          if oldElement.length == 0
            console.error "Wrong contextRoot in replaceTimeoutStub for #{ widget.debug() }!", $contextRoot
          result = DomHelper.replace(oldElement, $newRoot)
          result.then ->
            domInfo.domInserted()
          .then ->
            w.markShown() for w in affectedWidgets
            return
          result
        .then ->
          $newRoot


    @renderTemplateFile: (ownerWidget, fileName) ->
      ###
      Loads and renders the given template file of the given widget
      @param Widget ownerWidget
      @param String fileName file name relative to the widget's directory
      @return Future[String] rendered result
      ###
      tmplPath = "#{ ownerWidget.getTemplateDir() }/#{ fileName }.html"
      templateLoader.loadToDust(tmplPath).then ->
        Future.call(dust.render, tmplPath, ownerWidget.getBaseContext().push(ownerWidget.ctx))


    @getTimeoutHtml: (ownerWidget, timeoutTemplate, widget) ->
      ###
      Returns timeout-stub HTML depending on the presence of the timeout-stub template
      @param Widget ownerWidget
      @param String|null timeoutTemplate
      @return Future[String]
      ###
      if timeoutTemplate?
        @renderTemplateFile(ownerWidget, timeoutTemplate)
      else
        if widget?.constructor.defaultTimeoutTemplateString
          Future.resolved(widget.constructor.defaultTimeoutTemplateString)
        else
          Future.resolved('<img src="/bundles/cord/core/assets/pic/loader-transp.gif"/>')

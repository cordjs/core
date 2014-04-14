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
      @return Future
      ###
      Future.require('jquery', 'cord!utils/DomHelper').flatMap ($, DomHelper) ->
        $newRoot = $(widget.renderRootTag(html))
        widget.browserInit($newRoot).zip(domInfo.domRootCreated()).flatMap (any, $contextRoot) ->
          DomHelper.replaceNode($('#'+widget.ctx.id, $contextRoot), $newRoot)
      .zip(domInfo.domInserted()).map ->
        widget.markShown()
        []
      .failAloud()


    @renderTemplateFile: (ownerWidget, fileName) ->
      ###
      Loads and renders the given template file of the given widget
      @param Widget ownerWidget
      @param String fileName file name relative to the widget's directory
      @return Future[String] rendered result
      ###
      tmplPath = "#{ ownerWidget.getDir() }/#{ fileName }.html"
      templateLoader.loadToDust(tmplPath).flatMap ->
        Future.call(dust.render, tmplPath, ownerWidget.getBaseContext().push(ownerWidget.ctx))
      .failAloud()


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

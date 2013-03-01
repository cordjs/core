define [
  'jquery'
  './helper'
], ($, helper) ->

  class BrowserManager
    ###
    @browser-only
    ###

    constructor: ->
      @_loadedFiles = {}


    load: (cssFile) ->
      ###
      Adds css-file to the page if it is not already loaded
      ###
      if not @_loadedFiles[cssFile]?
#        console.log "CssManager::load(#{ cssFile })"
        $('head').append(helper.getHtmlLink cssFile)
        @_loadedFiles[cssFile] = true


    registerLoadedCssFiles: ->
      ###
      Scans page's link tags and registers already loaded css files in manager.
      This is needed to prevent double loading of the files when css files are on demand by client-side code.
      ###
      tmpLoaded = @_loadedFiles
      $("head > link[rel='stylesheet']").each ->
        tmpLoaded[$(this).attr('href')] = true



  new BrowserManager

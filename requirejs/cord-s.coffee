define [
  'module'
  'cord-helper'
], (module, helper) ->

  load: (name, req, onLoad, config) ->
    path = helper.getPathToCss name, config, module.id
    path = "#{ path }.css" if ! (path.split('.').pop().length <= 4)
    onLoad ''

  getLink: (path, emptyFileName) ->
    path = "#{ path }/#{ helper.getWidgetName path }" if emptyFileName
    path = "#{ path }.css" if ! (path.split('.').pop().length <= 4)
    path = helper.getPathToCss path

    path

  getHtml: ->
    path = @getLink arguments...
    @getHtmlLink path


  getHtmlLink: (path) ->
    "<link href=\"#{ path }\" rel=\"stylesheet\" />"

  insertCss: (path) ->
    path = @getLink arguments...
    require [ 'jquery' ], ($) ->
      if !$("head link[href='#{ path }']").length
        $('head').append( @getHtmlLink path );

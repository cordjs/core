define [
  'jquery.cookie'
  'underscore'
], ($, _) ->

  class BrowserCookie

    get: (name, defaultValue) ->
      $.cookie(name) ? defaultValue


    set: (name, value, params) ->
      _params = path: '/'
      _.extend(_params, params) if params
      $.cookie name, value, _params
      true

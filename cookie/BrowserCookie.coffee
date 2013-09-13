define [
  'jquery.cookie'
  'underscore'
], (cookie, _) ->

  class BrowserCookie

    get: (name, defaultValue) =>
      value = $.cookie name
      value ?= defaultValue

    set: (name, value, params) =>
      _params =
        path: '/'

      _params = _.extend _params, params if params

      $.cookie name, value, _params

      true

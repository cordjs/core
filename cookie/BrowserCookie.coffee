define [
  'jquery.cookie'
], (cookie) ->

  class BrowserCookie

    get: (name, defaultValue) =>
      value = $.cookie name
      value ?= defaultValue

    set: (name, value, params) =>
      $.cookie name, value,
        path: '/'

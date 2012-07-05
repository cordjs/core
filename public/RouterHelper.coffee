`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'postal'
], (postal) ->

  hashStrip = /^#*/

  class RouterHelper

    path: ''

    navigate: (args...) ->
      postal.publish 'router.navigate', args...

    getPath: ->
      path = window.location.pathname
      if path.substr(0,1) isnt '/'
        path = '/' + path
      path

    getHash: -> window.location.hash

    getFragment: -> @getHash().replace(hashStrip, '')

    getHost: ->
      (document.location + '').replace(@getPath() + @getHash(), '')

    getURLParameter: (name) ->
      (RegExp(name + '=' + '(.+?)(&|$)').exec(location.search)||[null,null])[1]
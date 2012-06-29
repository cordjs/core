`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], ->

  class Base

    test: (a) ->
      console.log a


  Base
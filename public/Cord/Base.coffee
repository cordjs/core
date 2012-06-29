`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], ->

  class Base

    @BaseKeywords = ['included', 'extended']

    @include: (obj) ->
      throw new Error('include(obj) requires obj') unless obj
      for key, value of obj when key not in @BaseKeywords
        @::[key] = value
      obj.included?.apply(this)
      this

    @extend: (obj) ->
      throw new Error('extend(obj) requires obj') unless obj
      for key, value of obj when key not in @BaseKeywords
        @[key] = value
      obj.extended?.apply(this)
      this

    @proxy: (func) ->
      => func.apply(this, arguments)

    proxy: (func) ->
      => func.apply(this, arguments)

    constructor: ->
      @init?(arguments...)


  Base
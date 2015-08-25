define [
  'cord!utils/include'
], (include) ->

  moduleKeywords = ['included', 'extended']

  class Module
    @include: (obj) ->
      include.call(this, obj)

    @extend: (obj) ->
      throw new Error('extend(obj) requires obj') unless obj
      for key, value of obj when key not in moduleKeywords
        @[key] = value
      obj.extended?.apply(this)
      this

    @proxy: (func) ->
      => func.apply(this, arguments)

    proxy: (func) ->
      => func.apply(this, arguments)

    constructor: ->
      @init?(arguments...)

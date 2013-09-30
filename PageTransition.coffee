define [], ->

  class PageTransition

    _active: true


    constructor: (@oldPath, @newPath) ->


    isActive: ->
      @_active


    interrupt: ->
      @_active = false


    if: (callback) ->
      transition = this
      (args...) ->
        callback.apply(this, args) if transition._active


    complete: ->
      @_active = false

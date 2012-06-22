`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [

], ->

  class Behaviour

    constructor: (view) ->
      @view = view
      @id = view.ctx.id
      console.log "behaviour constructor", @id
      @_setupBindings()

    _setupBindings: ->
      console.log "setup bindings"
      # do nothing, should be overriden
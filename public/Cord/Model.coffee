`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  './Base'
], (Base) ->

  class Model extends Base

    constructor: ->
      @test '!!!!!!!!Cord!!!!!!!!'


  Model
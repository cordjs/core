`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  './Base'
  './Model'
  './Controller'
], (Base, Model, Controller) ->

  class Cord

    @Base       = Base
    @Model      = Model
    @Controller = Controller

  Cord
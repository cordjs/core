`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  './Base'
  './Model'
], (Base, Model) ->
#  console.log Model

  class Cord

    @records: {}

    @Base = Base
    @Model = Model


  #  a = new MVC
#    console.log Cord.Model

  new Cord.Model
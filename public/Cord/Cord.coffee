`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  './Base'
  './Model'
], (Base, Model) ->
#  console.log Model

  console.log 'COOOORD'
  class Cord

    @records: {}

    @Base = Base
    @Model = Model

  Cord
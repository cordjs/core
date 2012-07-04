`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  '../Cord/Cord'
  '../Cord/lib/Ajax'
], (Cord) ->

  class TabModel extends Cord.Model

    @url: "/users"

  new TabModel
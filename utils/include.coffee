define ->

  moduleKeywords = ['included', 'extended']

  (obj) ->
    ###
    Includes a `obj`'s prototype to `this` prototype
    Usage example:

      include = require('cord!utils/include')
      EventEmitter = require('EventEmitter')
      Controller = require('Controller')
      SuperClass = require('SuperClass')

      class SomeClass extends SuperClass

        include.call(this, Controller)
        include.call(this, EventEmitter)

        constructor: ->
          # Don't forget to call extended constructors
          Controller.call(this)
          EventEmitter.call(this)
    ###
    throw new Error('include(obj) requires obj') unless obj
    for key, value of obj when key not in moduleKeywords
      @::[key] = value
    obj.included?.apply(this)
    this

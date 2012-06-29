`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], ->

    bind: (ev, callback) ->
      evs   = ev.split(' ')
      calls = @hasOwnProperty('_callbacks') and @_callbacks or= {}

      for name in evs
        calls[name] or= []
        calls[name].push(callback)
      this

    one: (ev, callback) ->
      @bind ev, ->
        @unbind(ev, arguments.callee)
        callback.apply(this, arguments)

    trigger: (args...) ->
      ev = args.shift()

      list = @hasOwnProperty('_callbacks') and @_callbacks?[ev]
      return unless list

      for callback in list
        if callback.apply(this, args) is false
          break
      true

    unbind: (ev, callback) ->
      unless ev
        @_callbacks = {}
        return this

      list = @_callbacks?[ev]
      return this unless list

      unless callback
        delete @_callbacks[ev]
        return this

      for cb, i in list when cb is callback
        list = list.slice()
        list.splice(i, 1)
        @_callbacks[ev] = list
        break
      this
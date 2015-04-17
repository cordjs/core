define [
  'cord!utils/Future'
  'underscore'
  'jquery'
], (Future, _, $) ->

  # max awaiting time, before auto-rejection
  _maxWaitingTime = 3000

  class TabSync
    ###
    Service for sharing common data and sync between browser tabs
    Browser only
    ###

    constructor: ->
      # Set of futures awaitng for localStorage event
      @_awaitingKeys = {}


    init: ->
      Future.try =>
        if window.localStorage?
          window.addEventListener("storage", @_handleStorageEvent, false);
          this
        else
          throw new Error('Your browser does not support localStorage.')


    set: (key, value) ->
      ###
      Set new value into tabs sync storage
      @param string key
      @param string value, if undefined - remove keyed value from storage
      ###
      if value == undefined
        localStorage.removeItem(key)
      else if _.isString(value)
        localStorage[key] = value
      else
        throw new Error('Only string values accepted in tabSync::set')


    get: (key) ->
      ###
      Returning current keyed value
      ###
      localStorage[key]


    waitFor: (key, timeout = _maxWaitingTime) ->
      ###
      Waits for keyed value to appear in tabs storage
      @param string key
      @param timeout - timeout, when result will be rejected
      ###
      if localStorage[key]
        Future.resolved(localStorage[key])
      else
        @_createAwaitingPromise(key, timeout)


    waitUntil: (key, timeout = _maxWaitingTime) ->
      ###
      Waits until keyed value disappear from localstorage
      result is rejected if key does not exists or timeouted, resolved if it existed and then disappeared
      @param string key
      @param timeout - timeout, when result will be rejected
      ###
      if localStorage[key] == undefined
        Future.rejected()
      else
        @_createAwaitingPromise(key, timeout)


    _createAwaitingPromise: (key, timeout) ->
      # Each awaiting request creates a new Future, not to let timeouts interfere
      @_awaitingKeys[key] or= []

      result = Future.single("tabSync::_createAwaitingPromise(#{key})")
      @_awaitingKeys[key].push(result)

      result.finally =>
        @_awaitingKeys[key] = _.without(@_awaitingKeys[key], result)

      setTimeout ->
        result.reject() if not result.completed()
      , timeout

      result


    _handleStorageEvent: (event) =>
      key = event.key 
      value = event.newValue
      _.each(@_awaitingKeys[key], (waitingPromise) -> waitingPromise.resolve(value))
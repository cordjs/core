define [
  'cord!utils/Future'
], (Future) ->

  class TabSyncServer
    ###
    Stub for server-side
    ###

    init: ->
      Future.resolved(this)


    set: (key, value) ->


    get: (key) ->


    waitFor: (key, timeout) ->
      Future.rejected()


    waitUntil: (key, timeout) ->
      Future.rejected()
define [
], ->

  class PersistentStorage

    initPromise: null

    constructor: (@storage) ->
      @values = {}
      @initPromise = @_getValues()


    get: (key) ->
      @initPromise.then =>
        @values[key]


    set: (key, value) ->
      @initPromise.then =>
        @values[key] = value
        @_saveValues()


    _getValues: ->
      @storage._get(@storage.persistentKey).then (values) =>
        @values = values
      .catch =>
        # если такого элемента в не существует - молча объявляем пустым
        @values = {}


    _saveValues: ->
      @initPromise.then =>
        @storage._set(@storage.persistentKey, @values)


define ->

  class PersistentStorage

    initPromise: null

    constructor: (@storage) ->
      @values = {}
      @initPromise = @_getValues()


    getItem: (key) ->
      @initPromise.then =>
        @values[key]


    get: @::getItem


    setItem: (key, value) ->
      @initPromise.then =>
        @values[key] = value
        @_saveValues()


    set: @::setItem


    _getValues: ->
      @storage._get(@storage.persistentKey).then (values) =>
        @values = values
      .catch =>
        # если такого элемента в не существует - молча объявляем пустым
        @values = {}


    _saveValues: ->
      @initPromise.then =>
        @storage._set(@storage.persistentKey, @values)


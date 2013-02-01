define [
  'cord!Module'
  'cord!Collection'
], (Module, Collection) ->

  class Model extends Module

    # list of field names actually loaded and used in this model
    # only attributes with this names are treated as model fields
    _fieldNames: null

    # old values of changed fields (by method set()) until the model is saved
    _changed: null


    constructor: (attrs) ->
      @_changed = {}
      @_load(attrs) if attrs


    _load: (attrs) ->
      @_fieldNames = []
      for key, value of attrs
        @[key] = value
        @_fieldNames.push(key)


    getChangedFields: ->
      result = {}
      for key of @_changed
        result[key] = @[key]
      result


    resetChangedFields: ->
      @_changed = {}


    setCollection: (collection) ->
      @collection = collection


    set: (key, val) ->
      if _.isObject(key)
        attrs = key
      else
        (attrs = {})[key] = val

      for key, val of attrs
        if not _.isEqual(@[key], val)
          @_changed[key] = @[key] if not @_changed[key]?
          @[key] = val
          @_fieldNames.push(key) if @_fieldNames.indexOf(key) == -1

      this


    # syntax sugar

    save: ->
      @collection.repo.save(this)


    on: (topic, callback) ->
      @collection.repo.on topic, (changed) =>
        if changed.id == @id
          callback(changed)


    # serialization related

    toJSON: ->
      result = {}
      for key in @_fieldNames
        result[key] = @[key]
      result


    serializeLink: ->
      ###
      Returns serialized link (address) of this model (including collection)
      @return String
      ###
      ":model:#{ @id }/#{ @collection.serializeLink() }"


    @isSerializedLink: (serialized) ->
      ###
      Detects if the given value is a serialized link to model
      @param Any serialized
      @return Boolean
      ###
      _.isString(serialized) and serialized.substr(0, 7) == ':model:'


    @unserializeLink: (serialized, ioc, callback) ->
      ###
      Converts serialized link to model to link of the model instance in it's collection
      @param String serialized
      @param Box ioc service container needed to get model repository service by name
      @param Function(Model) callback "returning" callback
      ###
      [modelId, serializedCollection] = serialized.substr(7).split('/')
      Collection.unserializeLink serializedCollection, ioc, (collection) ->
        callback(collection.get(modelId))

define [
  'cord!Module'
  'cord!Collection'
  'underscore'
], (Module, Collection, _) ->

  class Model extends Module

    # list of field names actually loaded and used in this model
    # only attributes with this names are treated as model fields
    _fieldNames: null

    # old values of changed fields (by method set()) until the model is saved
    _changed: null

    constructor: (attrs) ->
      ###
      attrs could be another model as well, ctor will return a copy of the original model
      ###

      @_fieldNames = []
      @_changed = {}
      if (attrs instanceof Model)
        attrs  = _.clone(attrs).toJSON()

      @_load(attrs) if attrs


    _load: (attrs) ->
      for key, value of attrs
        @[key] = @_deepClone value
        @_fieldNames.push(key)


    _deepClone: (value) ->

      if _.isArray(value)
        result = []
        for val in value
          result.push @_deepClone(val)
        return result
      else if _.isObject(value)
        result = {}
        for key, val of value
          result[key] = @_deepClone(val)
        return result
      return value


    getDefinedFieldNames: ->
      ###
      Returns list of the root names of the fields ever set for the model via constructor or set() method.
      'id' special field is not included.
      @return Array[String]
      ###
      @_fieldNames


    getChangedFields: ->
      # todo: why not _.clone(@_changed) ?
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
        key = key.toJSON() if key instanceof Model
        attrs = key
      else
        (attrs = {})[key] = val

      for key, val of attrs
        if not _.isEqual(@[key], val)
          @_changed[key] = @[key] if not @_changed[key]?
          @[key] = val
          @_fieldNames.push(key) if @_fieldNames.indexOf(key) == -1

      this


    refreshOnlyContainingCollections: ->
      #Make all collections, containing this model refresh
      #It's cheaper than Collection::checkNewModel and ModelRepo.suggestNewModelToCollections,
      #because mentioned ones make almost all collections refresh
      @collection.repo.refreshOnlyContainingCollections @


    propagateFieldChange: (fieldName, newValue) ->
      @collection.repo.propagateFieldChange @id, fieldName, newValue


    propagateModelChange: ->
      ###
      Propagate changed model in all collecion
      ###
      @collection.repo.propagateModelChange @


    emitLocalCalcChange: (path, val) ->
      ###
      Triggers correctly formed event about changing of some locally ad-hoc calculated field values of the model.
      The main purpose of this method is to propagate locally calculated value of the field to another model instances
       if they care about the field. It doesn't change the model in any way. If the model cares about the field, than
       the value will be changed by through the change-event listening in the model's collection.
      @param String|Object path dot-separated path of the value, or structure with field values
      @param Any val the new value for the field (applicable only if the first argument is String)
      ###
      if arguments.length == 1 and _.isObject(path)
        changeVal = _.clone(path)
      else
        # we have path -> value argument format, need to convert it to object-structure
        parts = path.split('.')
        lastPart = parts.pop()
        # special value that'll contain only structure with the changing value without any existing siblings
        changeVal = {}
        changePointer = changeVal

        # building structure based on dot-separated path
        for part in parts
          changePointer[part] = {}
          changePointer = changePointer[part]
        changePointer[lastPart] = val

      changeVal.id = @id
      @collection.repo.emit 'change', changeVal


    save: (notRefreshCollections = false) ->
      ###
      Save model via collection repo
      @param notRefreshCollections - if true caller must take care of collections refreshing
      ###
      if @collection?.repo?
        @collection.repo.save(this, notRefreshCollections)
      else
        throw new Error('Can not save model without collection')


    delete: ->
      ###
      Delete model via collection repo
      ###
      if @collection?.repo?
        @collection.repo.delete(this)
      else
        throw new Error('Can not delete model without collection')


    on: (topic, callback) ->
      ###
      Subscribe for this model instance related event
      @param String topic event topic (name)
      @param Function(data) callback callback function
      @return MonologueSubscription
      ###
      if @collection?
        if topic == 'change'
          # 'change'-event is conveniently proxy-triggered by the collection @see Collection::_handleModelChange
          @collection.on "model.#{ @id }.#{ topic }", callback
        else
          @collection.repo.on topic, (changed) =>
            callback(changed) if changed.id == @id


    # serialization related

    toJSON: ->
      result = {}
      for key in @_fieldNames
        value = @[key]
        result[key] = value

        if value instanceof Collection
          result[key] = value.serializeLink()
        else if value instanceof Model
          result[key] = value.serializeLink()
        else if _.isArray(value) and value[0] instanceof Model
          result[key] = (m.serializeLink() for m in value)

      result.id = @id
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

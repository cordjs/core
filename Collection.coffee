define [
  'cord!Module'
  'monologue' + (if document? then '' else '.js')
  'underscore'
], (Module, Monologue, _) ->

  class Collection extends Module
    #@include Monologue.prototype

    _filterType: ':none' # :none | :local | :backend
    _filterId: null
    _filterFunction: null

    _orderBy: ':id'

    _fields: null

    # correctly ordered list of models of the collection
    _models: null

    # index of models by id
    _byId: null

    _initialized: false


    @generateName: (options) ->
      ###
      Generates and returns unique "checksum" name of a collection depending only of the given options.
       This allows to reuse collections with the totally same options instead of duplicating them.
      @param Object options same options, that will be passed to the collection constructor
      @return String
      ###
      orderBy = options.orderBy ? ':id'
      filterId = options.filterId ? ''
      fields = options.fields ? []
      calc = options.calc ? []
      id = options.id ? 0

      (fields.sort().join(',') + '|' + calc.sort().join(',') + '|' + filterId + '|' + orderBy + '|' + id).replace(/\:/g, '')


    constructor: (@repo, @name, options) ->
      ###
      @param ModelRepo repo model repository to which the collection belongs
      @param String name unique name of the collection in the model repository
      @param Object options collection filtering, ordering and field fetching options
      ###
      @_models = []
      @_byId = {}
      @_orderBy = options.orderBy ? ':id'
      @_filterId = options.filterId ? null
      @_filterType = options.filterType ? ':backend'
      @_fields = options.fields ? []
      @_id = options.id ? 0


    sync: (returnMode, callback) ->
      ###
      Initiates synchronization of the collection with some backend and fires callback denending of given return mode
      @param String returnMode :sync -  return only after sync with server
                               :async - return immidiately if collection is initialized before, sync in background
                               :now -   return immidiately even if collection is not ever syncronized before,
                                        sync in background
                               :cache - return cached collection if initialized (without syncing),
                                        or perform like :sync otherwise

      @param Function(Collection) callback
      ###
      if _.isFunction(returnMode)
        callback = returnMode
        returnMode = ':sync'
      returnMode ?= ':sync'

      console.log "#{ @debug 'sync' } -> ", returnMode

      syncQuery = false
      if not (returnMode == ':cache' and @_initialized)
        queryParams = orderBy: @_orderBy
        queryParams.filterId = @_filterId if @_filterType == ':backend'
        queryParams.fields = @_fields
        queryParams.id = @_id if @_id
        @repo.query queryParams, (models) =>
          needCallback = not (@_initialized and syncQuery)
          syncQuery = true
          @_models = []
          @_byId = {}
          if @_filterType == ':local' and _.isFunction(@_filterFunction)
            @_models.push(model) if @_filterFunction(model)
          else
            @_models = models

          model.setCollection(this) for model in @_models
          @_reindexModels()
          @_initialized = true

          if returnMode == ':sync'
            callback(this)
          else if needCallback
            callback(this)

      if not syncQuery
        syncQuery = true
        switch returnMode
          when ':async', ':cache' then callback(this) if @_initialized
          when ':now'
            @_models = []
            @_byId = {}
            callback(this)


    get: (id) ->
      if @_byId[id]?
        @_byId[id]
      else
        throw new Error("There is no model with id = #{ id } in collection [#{ @debug() }]!")


    toArray: ->
      @_models


    _reindexModels: ->
      @_byId = {}
      @_byId[m.id] = m for m in @_models

    # serialization related

    toJSON: ->
      models: @_models
      filterType: @_filterType
      filterId: @_filterId
      orderBy: @_orderBy
      fields: @_fields


    @fromJSON: (repo, name, obj) ->
      collection = new this(repo, name, {})
      collection._models = (new repo.model(m) for m in obj.models)
      model.setCollection(collection) for model in collection._models
      collection._filterType = obj.filterType
      collection._filterId = obj.filterId
      collection._orderBy = obj.orderBy
      collection._fields = obj.fields

      collection._reindexModels()
      collection._initialized = (collection._models.length > 0)

      collection


    serializeLink: ->
      ###
      Returns serialized link (address) of this collection
      @return String
      ###
      ":collection:#{ @repo.constructor.name }:#{ @name }"


    @isSerializedLink: (serialized) ->
      ###
      Detects if the given value is a serialized link to collection
      @param Any serialized
      @return Boolean
      ###
      _.isString(serialized) and serialized.substr(0, 12) == ':collection:'


    @unserializeLink: (serialized, ioc, callback) ->
      ###
      Converts serialized link to collection to link of the collection instance from the model repository
      @param String serialized
      @param Box ioc service container needed to get model repository service by name
      @param Function(Collection) callback "returning" callback
      ###
      [repoClass, collectionName] = serialized.substr(12).split(':')
      repoServiceName = repoClass.charAt(0).toLowerCase() + repoClass.slice(1)
      ioc.eval repoServiceName, (repo) ->
        callback(repo.getCollection(collectionName))


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @constructor.name }(#{ @name })#{ methodStr }"

define [
  'cord!Module'
  'cord!utils/Future'
  'monologue' + (if document? then '' else '.js')
  'underscore'
], (Module, Future, Monologue, _) ->

  class Collection extends Module
    @include Monologue.prototype

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

    # partially loaded collection properties
    _loadedStart: 4294967295
    _loadedEnd: -1

    _hasLimits: null

    # helper value for event propagation optimization
    _selfEmittedChangeModelId: null


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

      # subscribe for model changes to smart-proxy them to the collections model instances
      @repo.on('change', @_handleModelChange).withContext(this)


    sync: (returnMode, params, callback) ->
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
        params = {}
      else if _.isFunction(params)
        callback = params
        params = {}
      returnMode ?= ':sync'

      console.log "#{ @debug 'sync' } -> ", returnMode, @_loadedStart, @_loadedEnd

      syncQuery = false
      if not (returnMode == ':cache' and @_initialized)
        queryParams =
          fields: @_fields
        if @_id
          queryParams.id = @_id
        else
          queryParams.orderBy = @_orderBy
          queryParams.filterId = @_filterId if @_filterType == ':backend'
          queryParams.start = params.start if params.start?
          queryParams.end = (params.end + 1)  if params.end?
        @repo.query queryParams, (models) =>
          needCallback = not (@_initialized and syncQuery)
          syncQuery = true
          if queryParams.start? and queryParams.end?
            loadingStart = params.start
            loadingEnd = params.end

            # appending/replacing new models to the collection according to the paging options
            for model, i in models
              model.setCollection(this)
              @_models[loadingStart + i] = model

            @_loadedStart = loadingStart if loadingStart < @_loadedStart
            @_loadedEnd = loadingEnd if loadingEnd > @_loadedEnd

            @_hasLimits = (@_hasLimits != false)

          else
            @_models = models
            @_loadedStart = 0
            @_loadedEnd = models.length - 1
            @_hasLimits = false

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


    isInitialized: ->
      ###
      Indicates that the collection is already synchronized at least once.
      @return Boolean
      ###
      @_initialized


    checkNewModel: (model) ->
      ###
      Checks if the new model is related to this collection. If it is reloads collection from the backend.
      @param Model model the new model
      ###
      if not @_id
        queryParams = @_buildRefreshQueryParams()
        @repo.query queryParams, (models) =>
          newId = model.id
          found = false
          for m in models
            if m.id == newId
              found = true
              break
          if found
            @_fillModelList models, queryParams.start, queryParams.end


    refresh: ->
      ###
      Reloads currently loaded part of collection from the backend.
      By the way triggers change events for every changed model and for the collection if there are any changes.
      todo: support of single-model collections
      ###
      queryParams = @_buildRefreshQueryParams()
      @repo.query queryParams, (models) =>
        @_fillModelList models, queryParams.start, queryParams.end


    _reindexModels: ->
      ###
      Rebuilds useful index of the models by their id.
      ###
      @_byId = {}
      for m in @_models
        if m != undefined
          @_byId[m.id] = m


    _buildRefreshQueryParams: ->
      ###
      Builds backend query params for the currently defined collection params to refresh collection items.
      @return Object key-value params for the ModelRepo::query() method
      ###
      result =
        orderBy: @_orderBy
        fields: @_fields
      result.filterId = @_filterId if @_filterType == ':backend'
      if @_hasLimits
        result.start = @_loadedStart
        result.end = @_loadedEnd
      result


    _fillModelList: (newList, start, end) ->
      ###
      Substitutes part of list of models with the new ones comparing them by the way and triggering according events.
      If start and end arguments are not given, then the whole list is replaced starting from index 0.
      @param Array[Model] newList list of new models
      @param (optional)Int start starting index of the destination list, from which should replacement started
      @param (optional)Int end index of last item to replace
      ###
      if start? and end?
        loadingStart = start
        loadingEnd = end
        @_models = _.clone(@_models)
      else
        loadingStart = 0
        loadingEnd = newList.length - 1
        @_models = []

      changed = false
      # appending/replacing new models to the collection according to the paging options
      for model, i in newList
        model.setCollection(this)
        if @_byId[model.id]? and @_compareModels(model, @_byId[model.id])
          changed = true
          @emit "model.#{ @_selfEmittedChangeModelId }.change", model
          @emitModelChangeExcept(model) # todo: think about 'sync' event here
        targetIndex = loadingStart + i
        changed = true if not @_models[targetIndex]? or model.id != @_models[targetIndex].id
        @_models[targetIndex] = model

      @_loadedStart = loadingStart if loadingStart < @_loadedStart
      @_loadedEnd = loadingEnd if loadingEnd > @_loadedEnd

      @_reindexModels()

      @emit 'change' if changed


    _compareModels: (model1, model2) ->
      ###
      Deeply compares two models using only fields of this collection.
      @param Model model1
      @param Model model2
      @return Boolean true if models differ, false if they are the same
      ###
      return true if model1.id != model2.id
      for field in model1.getDefinedFieldNames()
        if field != 'id' and not _.isEqual(model1[field], model2[field])
          return true
      return false


    emitModelChangeExcept: (model) ->
      ###
      Triggers 'change' event for the model preventing duplicate checking and modifying the model in this collection
       when emitModelChange is called
      @param Model model
      ###
      @_selfEmittedChangeModelId = model.id
      @repo.emitModelChange(model)
      @_selfEmittedChangeModelId = null


    _recursiveCompareAndChange: (src, dst) ->
      ###
      Deeply rewrites values from the source object to the corresponding keys of the destination object.
      Only existing keys of the destination model are changed, no new keys are added.
      If the value is object than recursively calls itself.
      @param Object src source object
      @param Object dst destination object
      @return Boolean true if the destination object was changed
      ###
      result = false
      for key, val of src
        if dst[key] != undefined
          if _.isArray(val) or not _.isObject(val)
            if not _.isEqual(val, dst[key])
              dst[key] = _.clone(val)
              result = true
          else if @_recursiveCompareAndChange(val, dst[key])
            result = true
      result


    _handleModelChange: (changeInfo) ->
      ###
      Model's 'change'-event smart proxy filter and propagator.
      Converts ModelRepo's 'change' event with {id: 2, changedField: 'newValue'}
       to Collection's 'model.2.change' event with mutated with changedField collections
      Mutates collection's matching model.
      @
      ###
      if (model = @_byId[changeInfo.id])?
        if @_selfEmittedChangeModelId != changeInfo.id and @_recursiveCompareAndChange(changeInfo, model)
          @emit "model.#{ changeInfo.id }.change", model


    # paging related

    getPage: (firstPage, lastPage, size) ->
      ###
      Obtains and returns in future portion of models of the collection according to given paging params
      If the second argument is omitted than only one page is returned.
      @param Int firstPage number of the first page
      @param (optional)Int lastPage number of the last page
      @param Int size page size
      @return Future(Array[Model])
      ###
      if arguments.length == 2
        size = lastPage
        lastPage = firstPage

      start = (firstPage - 1) * size
      end = start + size * (lastPage - firstPage + 1) - 1

      slice = => @toArray().slice(start, end + 1)

      promise = (new Future).fork()
      if @_loadedStart <= start and @_loadedEnd >= end
        promise.resolve(slice())
      else
        [loadStart, loadEnd] = @_calculateLoadPageOptions(start, end)

        @sync ':sync',
          start: loadStart
          end: loadEnd
        , ->
          promise.resolve(slice())

      promise


    _calculateLoadPageOptions: (start, end) ->
      ###
      Calculate optimal page number and size for the needed range
      @param Int start starting position needed
      @param Int end ending position needed
      @return [Int, Int] tuple with page number and page size to request from backend
      ###
      loadStart = if start < @_loadedStart then start else @_loadedEnd + 1
      loadEnd = if end > @_loadedEnd then end else @_loadedStart - 1
      [loadStart, loadEnd]


    # serialization related

    toJSON: ->
      models: @_models
      filterType: @_filterType
      filterId: @_filterId
      orderBy: @_orderBy
      fields: @_fields
      start: @_loadedStart
      end: @_loadedEnd
      hasLimits: @_hasLimits


    @fromJSON: (repo, name, obj) ->
      collection = new this(repo, name, {})
      collection._models = (repo.buildModel(m) for m in obj.models)
      model.setCollection(collection) for model in collection._models
      collection._filterType = obj.filterType
      collection._filterId = obj.filterId
      collection._orderBy = obj.orderBy
      collection._fields = obj.fields
      collection._loadedStart = obj.start
      collection._loadedEnd = obj.end
      collection._hasLimits = obj.hasLimits

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
      "#{ @repo.constructor.name }::#{ @constructor.name }#{ methodStr }"

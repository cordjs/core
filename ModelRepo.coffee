define [
  'cord!Collection'
  'cord!Model'
  'cord!Module'
  'cord!isBrowser'
  'cord!utils/Defer'
  'cord!utils/Future'
  'underscore'
  'monologue' + (if CORD_IS_BROWSER then '' else '.js')
], (Collection, Model, Module, isBrowser, Defer, Future, _, Monologue) ->

  class ModelRepo extends Module
    @include Monologue.prototype

    model: Model

    _collections: null

    _collectedTags: null

    restResource: ''

    predefinedCollections: null

    # @type Map[String: (Any, Any) -> Boolean]
    # If it is defined for a field, the function is used as compare method for that field.
    # The function must return true if values are different.
    fieldCompareFunctions: null

    fieldTags: null

    # key-value of available additional REST-API action names to inject into model instances as methods
    # key - action name
    # value - HTTP-method name in lower-case (get, post, put, delete)
    # @var Object[String -> String]
    actions: null

    @inject: ['api', 'modelProxy']


    constructor: (@container) ->
      throw new Error("'model' property should be set for the repository!") if not @model?

      @_collections = {}

      @_collectedTags = {}

      @_initPredefinedCollections()


    init: ->


    _initPredefinedCollections: ->
      ###
      Initiates hard-coded collections with their names and options based on the predefinedCollections proprerty.
      ###
      if @predefinedCollections?
        for name, options of @predefinedCollections
          collection = new Collection(this, name, options)
          @_registerCollection(name, collection)


    createCollection: (options) ->
      ###
      Just creates, registers and returns a new collection instance of existing collection if there is already
       a registered collection with the same options.
      @param Object options
      @return Collection
      ###

      if options.collectionClass
        throw new Error("Extended collections should be created using ModelRepo::createExtendedCollection() method!")
      name = options.collectionName or Collection.generateName(options)
      if @_collections[name]? and @_collections[name].isConsistent() and not options.renew
        collection = @_collections[name]
      else
        options = _.clone(options)
        @_collections[name] = null

        if _.isObject(options.rawModelsData)
          options.models = []
          options.models.push(@buildModel(item)) for item in options.rawModelsData

        collection = new Collection(this, name, options)
        @_registerCollection(name, collection)

      # We need to reinject tags because some of them could be user-functions
      collection.injectTags(options.tags)
      collection


    euthanizeCollection: (collection) ->
      ###
      Removes collection from @_collections and clear it's cache
      @return Future which resolves when cache is cleared
      ###
      delete @_collections[collection.name]
      @invalidateCollectionCache(collection.name)


    createExtendedCollection: (collectionClass, options) ->
      ###
      Creates extended collection using the given collection class. Besides just calling the class constructor
       services are injected and browserInit method is called before returning the result (async).
      @param Function collectionClass extended collection class constructor
      @param Object options common collection options
      @return Future(Collection)
      ###
      options.collectionClass = collectionClass
      name = Collection.generateName(options)

      if @_collections[name]?
        # We need to reinject tags because some of them could be user-functions
        @_collections[name].injectTags(options.tags)
        Future.resolved(@_collections[name])
      else
        CollectionClass = options.collectionClass ? Collection
        collection = new CollectionClass(this, name, options)
        @_registerCollection(name, collection)

        @container.injectServices(collection).then =>
          # We need to reinject tags because some of them could be user-functions
          @_collections[name].injectTags(options.tags)
          collection.browserInit?()  if isBrowser
          collection


    buildCollection: (options, syncMode, callback) ->
      ###
      Creates, syncs and returns in callback a new collection of this model type by the given options.
       If collection with the same options is already registered than this collection is returned
       instead of creating the new one.

      @see Collection::constructor()

      @param Object options should contain options accepted by collection constructor
      @param (optional)String syncMode desired sync and return mode, defaults to :sync
      @param Function(Collection) callback
      @return Collection
      ###

      if _.isFunction(syncMode)
        callback = syncMode
        syncMode = ':sync'

      collection = @createCollection(options)
      collection.sync(syncMode, callback)
      collection


    createSingleModel: (id, fields, extraOptions = {}) ->
      ###
      Creates single-model collection by id and field list.
      Method returns single-model collection.

      @param Integer id
      @param Array[String] fields list of fields names for the collection
      @return Collection|null
      ###

      # extraOptions should not override option keys defined here
      options = _.extend {}, extraOptions,
        id: id
        fields: fields
        reconnect: false

      @createCollection(options)


    buildSingleModel: (id, fields, syncMode, extraOptions = {}) ->
      ###
      Creates and syncs single-model collection by id and field list.
      Method returns promise with the model instance.

      :now sync mode is not available here since we need to return the resulting model.

      @param {Integer} id
      @param {Array<String>} fields - list of fields names for the collection
      @param (optional){String} syncMode - desired sync and return mode, default to :cache
             special sync mode :cache-async, tries to find model in existing collections,
             if not found, calls sync in async mode to refresh model
      @return {Future<Model>}
      ###
      if syncMode == ':cache' or syncMode == ':cache-async'
        model = @probeCollectionsForModel(id, fields)

        if model
          return Future.try =>
            collection = @createCollection
              fields: fields
              id: model.id
              model: @buildModel(model)

            collection.get(id)

      syncMode = ':async' if syncMode == ':cache-async'

      @createSingleModel(id, fields, extraOptions)
        .sync(syncMode, 0, 0)
        .then (collection) ->
          collection.get(id)


    probeCollectionsForModel: (id, fields) ->
      ###
      Searches existing collections for needed model
      @param Integer id - id of needed model
      @param Array[String] fields list of fields names for a model
      @return Object|null - model or null if not found
      ###
      if (_.isArray fields)
        matchedCollections = @scanCollections(fields)
      else
        matchedCollections = _.values @_collections

      for collection in matchedCollections
        if collection.have(id)
          return collection.get(id)

      null


    #Get collections matching fields
    scanCollections: (scannedFields) ->
      _.filter @_collections, (collection, key) ->
        found = 0
        for field in scannedFields
          if _.indexOf(collection._fields, field) > -1 || field == 'id'
            found += 1
        if found == scannedFields.length then true else false


    sizeOfAllCollections: ->
      _.reduce @_collections, (memo, value, index) ->
        memo + value._models.length
      , 0


    scanLoadedModels: (scannedFields, searchedText, limit, requiredFields) ->
      ###
      Scans existing collections for models, containing searchedText
      @param Array[String] scannedFields - model fields to be scanned, only collections, having all the fields will be scanned
      @param String searchedText
      @param limit - max amout of returned models
      @param Array[String] requiredFields - scan only collections with model, having all required fields
      ###
      if !requiredFields
        requiredFields = scannedFields

      options=
        fields: requiredFields

      matchedCollections = @scanCollections(requiredFields)
      result = {}
      for collection in matchedCollections
        foundModels = collection.scanModels scannedFields, searchedText, limit
        result = _.extend result, foundModels
        if limit
          limit -= _.size foundModels
          if limit <= 0
            break

      options =
        fixed: true
        models: result
        fields: requiredFields

      new Collection(this, 'fixed', options)


    collectionExists: (name) ->
      ###
      Checks if a collection with the given name is already registered in this repo
      @param {String} name
      @return {Boolean}
      ###
      @_collections[name]?


    getCollection: (name, returnMode, callback) ->
      ###
      Returns registered collection by name. Returns collection immediately anyway regardless of
       that given in returnMode and callback. If returnMode is given than callback is required and called
       according to the returnMode value. If only callback is given, default returnMode is :now.

      @param String name collection's unique (in the scope of the repository) registered name
      @param (optional)String returnMode defines - when callback should be called
      @param (optional)Function(Collection) callback function with the resulting collection as an argument
                                                     to be called when returnMode decides
      ###
      if @_collections[name]?
        if _.isFunction(returnMode)
          callback = returnMode
          returnMode = ':now'
        else
          returnMode or= ':now'

        collection = @_collections[name]

        if returnMode == ':now'
          callback?(collection)
        else if callback?
          collection.sync(returnMode, callback)
        else
          throw new Error("Callback can be omitted only in case of :now return mode!")

        collection
      else
        throw new Error("There is no registered collection with name '#{ name }'!")


    _registerCollection: (name, collection) ->
      ###
      Validates and registers the given collection
      ###
      if @_collections[name]?
        throw new Error("Collection with name '#{ name }' is already registered in #{ @constructor.__name }!")
      if not (collection instanceof Collection)
        throw new Error("Collection should be inherited from the base Collection class!")

      @_collections[name] = collection


    _fieldHasTag: (fieldName, tag) ->
      @fieldTags? and @fieldTags[fieldName]? and _.isArray(@fieldTags[fieldName]) and @fieldTags[fieldName].indexOf(tag) != -1


    # serialization related:

    toJSON: ->
      @_collections


    setCollections: (collections) ->
      ###
      Restores the repository collections from the serialized data passed from the server-side to the browser-side.
      @param Object(String -> Object) collections key-value with collection name as a key and serialized collection info
                                      as a value
      @browser-only
      ###
      result = new Future('ModelRepo::setCollections result')
      @_collections = {}
      for name, info of collections
        do (info, name) =>
          collectionClassPromise =
            if info.canonicalPath?
              Future.require("cord-m!#{ info.canonicalPath }")
            else
              Future.resolved(Collection)

          collectionClassPromise.then (CollectionClass) =>
            info.collectionClass = CollectionClass
            collection = Collection.fromJSON(this, name, info)
            #Assume that collection from backend is always fresh
            collection.updateLastQueryTime()
            @_registerCollection(name, collection)
            @container.injectServices(collection).then ->
              collection.browserInit?()
              return
          .link(result)
      result


    # REST related

    query: (params, callback) ->
      if @container
        apiParams = {}
        apiParams.reconnect = true if params.reconnect == true
        url = @_buildApiRequestUrl(params)

        @api.get(url, apiParams).then (response) =>
          if not response._code  #Bad boy! Quickfix for absence of error handling
            result = []
            if _.isArray(response)
              result.push(@buildModel(item)) for item in response
            else if response
              result.push(@buildModel(response))
            callback?(result)
            [result] ## todo: Future refactor
          else
            throw new Error("#{@debug('query')}: invalid response for url '#{url}' with code #{response._code}!")
      else
        Future.rejected(new Error('Cleaned up'))


    _buildApiRequestUrl: (params) ->
      ###
      Build URL for api request
      @param Object params paging and collection params
      @return String
      ###
      urlParams = []
      urlParams.push("_sortby=#{ params.orderBy }") if params.orderBy?
      if not params.id?
        urlParams.push("_filter=#{ params.filterId }") if params.filterId?
        urlParams.push("_filterParams=#{ params.filterParams }") if params.filterParams?
        urlParams.push("_reportConfig=#{ params.reportConfig }") if params.reportConfig?
        urlParams.push("_page=#{ params.page }") if params.page?
        urlParams.push("_pagesize=#{ params.pageSize }") if params.pageSize?
        # important! adding 1 to the params.end to compensate semantics:
        #   in the backend 'end' is meant as in javascript's Array.slice() - "not including"
        #   but in collection end is meant as the last index - "including"
        urlParams.push("_slice=#{ params.start },#{ params.end + 1 }") if params.start? or params.end?
        if params.filter
          for filterField, filterValue of params.filter
            if _.isArray filterValue
              for filterValueItem in filterValue
                urlParams.push("#{ filterField }[]=#{ filterValueItem }")
            else
              urlParams.push("#{ filterField }=#{ filterValue }")

      if params.requestParams
        for requestParam of params.requestParams
          urlParams.push("#{ requestParam }=#{ params.requestParams[requestParam] }")

      commonFields = []
      calcFields = []
      for field in params.fields
        if @_fieldHasTag(field, ':backendCalc')
          calcFields.push(field)
        else
          commonFields.push(field)
      if commonFields.length > 0
        urlParams.push("_fields=#{ commonFields.join(',') }")
      else
        urlParams.push("_fields=id")
      urlParams.push("_calc=#{ calcFields.join(',') }") if calcFields.length > 0

      @restResource + (if params.accessPoint? then ('/' + params.accessPoint) else '') + (if params.id then '/' + params.id + '/?'  else '/?') + urlParams.join('&')


    delete: (model) ->
      ###
      Remove given model on the backend
      @param Model model model to save
      @return {Future<Object>}
      ###
      if model.id
        @api.del(@restResource + '/' + model.id).then (response) =>
          @clearSingleModelCollections(model).then =>
            @refreshOnlyContainingCollections(model)
            response
        .catch (err) =>
          @emit 'error', err
          throw err
      else
        Future.rejected(new Error("#{@debug('delete')} - model is not saved yet. Can't delete: #{model}"))


    save: (model, notRefreshCollections = false) ->
      ###
      Persists list of given models to the backend
      @param model model model to save
      @param notRefreshCollections - if true caller must take care of collections refreshing
      @return {Future<Object>}
      ###
      if model.id
        changeInfo = model.getChangedFields()
        # Don't do api request if model isn't change
        if Object.keys(changeInfo).length
          pureChangeInfo = _.clone(changeInfo)
          changeInfo.id = model.id
          changeInfo._sourceModel = model
          @emit 'change', changeInfo
          @api.put(@restResource + '/' + model.id, model.getChangedFields()).then (response) =>
            @cacheCollection(model.collection) if model.collection?
            model.resetChangedFields()
            @emit 'sync', model
            if not notRefreshCollections
              @triggerTagsForChanges(pureChangeInfo, model)
            response
          .catch (err) =>
            @emit 'error', err
            throw err
        else
          Future.resolved() # todo: may be model.toJSON() would be more sufficient here?
      else
        @api.post(@restResource, model.getChangedFields()).then (response) =>
          model.id = response.id
          model.resetChangedFields()
          @emit 'sync', model
          @triggerTagsForNewModel(model, response) if not notRefreshCollections
          @_injectActionMethods(model)
          response
        .catch (err) =>
          @emit 'error', err
          throw err


    triggerTagsForNewModel: (model, response) ->
      ###
      Merger response fields with model and trigger change.
      Because backend could do anything with the fields values, like put defaults, etc
      ###
      cloneModel = _.clone(model)
      _.extend(cloneModel, response)
      @triggerTagsForChanges(cloneModel, cloneModel)


    triggerTagsForChanges: (changeInfo, model) ->
      ###
      Analyse changeInfoOrModel and trigger according tags
      ###
      model = changeInfo if changeInfo instanceof Model

      @triggerTag("id.any", model)
      @triggerTag("id.#{model.id}", model)

      for fieldName, value of changeInfo
        continue if _.isFunction(value) or not fieldName or fieldName[0] == '_' # _Ignore _any _private _parts of the object
        @triggerTag("#{fieldName}.any", model)
        if _.isObject(value)
          if value.id
            @triggerTag("#{fieldName}.#{value.id}", model)
        else
          @triggerTag("#{fieldName}.#{value}", model)


    # Triggers tags actions on all collections
    # @params tag - string
    # @params mods - anythings
    triggerTag: (tag, mods) ->
      @_collectedTags[tag] = mods

      Defer.nextTick =>
        _console.log('Emit tags:', @_collectedTags) if _.size(@_collectedTags) > 0 and global.config.debug.model
        @emit('tags', @_collectedTags) if _.size(@_collectedTags) > 0
        @_collectedTags = {}


    paging: (params) ->
      ###
      Requests paging information from the backend.
      @param Object params paging and collection params
      @return Future(Object)
                total: Int (total count this collection's models)
                pages: Int (total number of pages)
                selected: Int (0-based index/position of the selected model)
                selectedPage: Int (1-based number of the page that contains the selected model)
      ###
      @api.get(@_buildPagingRequestUrl(params))


    _buildPagingRequestUrl: (params) ->
      ###
      Build URL for paging request
      @param Object params paging and collection params
      @return String
      ###
      urlParams = []
      urlParams.push("_filter=#{ params.filterId }") if params.filterId?
      urlParams.push("_filterParams=#{ params.filterParams }") if params.filterParams?
      urlParams.push("_reportConfig=#{ params.reportConfig }") if params.reportConfig?
      urlParams.push("_pagesize=#{ params.pageSize }") if params.pageSize?
      urlParams.push("_sortby=#{ params.orderBy }") if params.orderBy?
      urlParams.push("_selectedId=#{ params.selectedId }") if params.selectedId

      if params.filter
        for filterField, filterValue of params.filter
          if _.isArray filterValue
            for filterValueItem in filterValue
              urlParams.push("#{ filterField }[]=#{ filterValueItem }")
          else
            urlParams.push("#{ filterField }=#{ filterValue }")

      if params.requestParams
        for requestParam of params.requestParams
          urlParams.push("#{ requestParam }=#{ params.requestParams[requestParam] }")

      @restResource + '/paging/?' + urlParams.join('&')


    ###
    TODO: От этого метода надо отказаться, после отказа от MixModelList
    ###
    _buildPagingRequestParams: (params) ->
      ###
      Build api params for paging request
      @param Object params paging and collection params
      @return Object
      ###
      apiParams = {}
      apiParams._pagesize = params.pageSize if params.pageSize?
      apiParams._sortby = params.orderBy if params.orderBy?
      apiParams._selectedId = params.selectedId if params.selectedId?
      apiParams._filter = params.filterId if params.filterId?
      apiParams._filterParams = params.filterParams if params.filterParams?
      apiParams._reportConfig = params.reportConfig if params.reportConfig?
      if params.filter
        for filterField of params.filter
          apiParams[filterField] = params.filter[filterField]
      apiParams


    emitModelChange: (model) ->
      ###
      Call this if model's current state (not changeset) has to be propagated into all collections
      @param Model - model
      ###
      if model instanceof Model
        changeInfo = model.toJSON()
        changeInfo.id = model.id
      else
        changeInfo = model
      @emit 'change', changeInfo


    propagateModelChange: (model) ->
      ###
      Model changed by set() or setAloud() method and needs to be updated in all collections
      @param Model - model
      ###
      changeInfo = model.getChangedFields()

      if Object.keys changeInfo
        changeInfo.id = model.id
        @emit 'change', changeInfo
        @suggestNewModelToCollections(model)


    propagateFieldChange: (id, fieldName, newValue) ->
      ###
      Fixes that particular field has been changed and needs to be updated in all collections
      @param id Int - model id
      @param fieldName String - changed field name
      @param newValue mixed - new value for the object
      ###

      #Collect field definition in all collections
      fieldDefinitions = []
      nameLength = fieldName.length
      for key,collection of @_collections
        fieldDefinitions = _.union fieldDefinitions, _.filter(collection._fields, (item) ->
          item.substr(0, nameLength) == fieldName
        )

      if fieldDefinitions.length == 0
        return

      # Check if we need to make a request
      needRequest = false
      for fieldDefinition in fieldDefinitions
        subFields = fieldDefinition.split '.'
        currentValue = newValue
        for i in [1..subFields.length]
          if currentValue == undefined
            needRequest = true
            break
          currentValue = currentValue[subFields[i]]
        break  if needRequest

      #Do request, or not
      Future.try =>
        if needRequest
          @api.get @restResource + '/' + id,
            _fields: fieldDefinitions.join(',')
        else
          changeset = {}
          changeset[fieldName] = newValue
          changeset

      .then (changeset) =>
        #Propagate new value
        changeset.id = id
        for key,collection of @_collections
          collection._handleModelChange changeset
        return


    callModelAction: (id, method, action, params) ->
      ###
      Request REST API action method for the given model
      @param Scalar id the model id
      @param String action the API action name on the model
      @param Object params additional key-value params for the action request (will be sent by POST)
      @return Future[response]
      ###
      @api[method]("#{ @restResource }/#{ id }/#{ action }", params)


    buildModel: (attrs) ->
      ###
      Model factory.
      @param Object attrs key-value fields for the model, including the id (if exists)
      @return Model
      ###
      result = new @model(attrs)

      if @modelProxy
        for key, value of attrs
          if Collection.isSerializedLink(value)
            @modelProxy.addCollectionLink result, key
          else if Model.isSerializedLink(value)
            @modelProxy.addModelLink result, key
          else if _.isArray(value) and Model.isSerializedLink(value[0])
            @modelProxy.addArrayLink result, key

      @_injectActionMethods(result) if attrs?.id

      result


    buildNewModel: (attrs) ->
      ###
      Model factory.
      Unlike buildModel() set input attributes in changed fields. It is important for future saving
      @param Object attrs key-value fields for the model, including the id (if exists)
      @return Model
      ###
      result = new @model()

      # Clear functions
      safeAttrs = {}
      for key, value of attrs
        safeAttrs[key] = value if not _.isFunction(value)

      result.set safeAttrs

      @_injectActionMethods(result) if attrs?.id

      result


    refreshOnlyContainingCollections: (model) ->
      #Make all collections, containing this model refresh
      #It's cheaper than Collection::checkNewModel and ModelRepo.suggestNewModelToCollections,
      #because mentioned ones make almost all collections refresh
      @triggerTag('id.any', model)
      @triggerTag("id.#{ model.id }", model)


    refreshAll: ->
      # Force refreshing all collections
      # Depricated
      _console.warn('ModelRepo.refreshAll is depricated.')
      Defer.nextTick =>
        for name, collection of @_collections
          collection.partialRefresh(1, 1, 0)


    clearSingleModelCollections: (model) ->
      #Clear cache and single model collections
      promise = new Future('ModelRepo::clearSingleModelCollections')
      for key, collection of @_collections
        if parseInt(collection._id) == model.id
          promise.when(collection.euthanize())
      promise


    invalidateAllCache: ->
      ###
      Invalidates cache for all collections
      @return {Future<undefined>}
      ###
      @_collections = {}
      if isBrowser
        @container.getService('localStorage').then (storage) =>
          storage._invalidateAllCollections(@constructor.__name) #Invalidate All
      else
        Future.resolved()


    invalidateCacheForCollectionWithField: (fieldName) ->
      ###
      Invalidates cache for all collections with the field name
      @return {Future<undefined>}
      ###
      for key, collection of @_collections
        if collection._fields.indexOf(fieldName) >= 0
          delete @_collections[key]

      if isBrowser
        @container.getService('localStorage').then (storage) =>
          storage.invalidateAllCollectionsWithField(@constructor.__name, fieldName)
      else
        Future.resolved()


    invalidateCacheForCollectionsWithFilter: (fieldName, filterValue) ->
      ###
      Invalidate cache for all collections where filter contains fieldName=filterVaue
      ###
      result = new Future('ModelRepo::invalidateCacheForCollectionsWithFilter')

      for key, collection of @_collections
        if collection._filter[fieldName] == filterValue
          if isBrowser
            result.when(collection.invalidateCache())
          delete @_collections[key]

      result


    suggestNewModelToCollections: (model) ->
      ###
      Notifies all available collections to check if they need to refresh with the new model
      ###
      Defer.nextTick =>
        for name, collection of @_collections
          collection.clearLastQueryTime()
          collection.checkNewModel(model, false)


    _injectActionMethods: (model) ->
      ###
      Dynamically injects syntax-sugar-methods to call REST-API actions on the model instance as method-call
       with the name of the action. List of available action names must be set in the @action property of the
       model repository.
      @param Model model model which is injected with the methods
      @return Model the incoming model with injected methods
      ###
      if @actions?
        self = this
        for actionName, method of @actions
          do (actionName, method) ->
            model[actionName] = (params) ->
              self.callModelAction(@id, method, actionName, params)
      model


    getTtl: ->
      ###
      local caching related
      ###
      600


    cacheCollection: (collection) ->
      ###
      Stores the given collection in the browser's local storage
      @param {Collection} collection
      @return {Future[Bool]} true if collection cached successfully, false otherwise
      ###
      name = collection.name
      if isBrowser
        @container.getService('localStorage').then (storage) =>
          # prepare models for cache
          models = []
          models[key] = model.toJSON() for key, model of collection.toArray()

          saveInfoPromise = storage.saveCollectionInfo @constructor.__name, name, collection.getTtl(),
            totalCount: collection._totalCount
            start: collection._loadedStart
            end: collection._loadedEnd
            hasLimits: collection._hasLimits
            fields: collection._fields
          Future.all [
            saveInfoPromise
            storage.saveCollection(@constructor.__name, name, models)
          ]
          .then ->
            true
          .catch (err) ->
            _console.error "#{@constructor.__name}::cacheCollection() failed:", err
            false
      else
        Future.resolved(false)


    cutCachedCollection: (collection, loadedStart, loadedEnd) ->
      if isBrowser
        @container.getService('localStorage').then (storage) =>
          storage.saveCollectionInfo @constructor.__name, collection.name, null,
            totalCount: collection._totalCount
            start: loadedStart
            end: loadedEnd
            fields: collection._fields
      else
        Future.rejected(new Error('ModelRepo::cutCachedCollection is not applicable on server-side!'))


    getCachedCollectionInfo: (name) ->
      if isBrowser
        @container.getService('localStorage').then (storage) =>
          storage.getCollectionInfo(@constructor.__name, name)
      else
        Future.rejected(new Error('ModelRepo::getCachedCollectionInfo is not applicable on server-side!'))


    getCachedCollectionModels: (name) ->
      if isBrowser
        @container.getService('localStorage').then (storage) =>
          storage.getCollection(@constructor.__name, name)
        .then (models) =>
          result = []
          for m, index in models
            result[index] = @buildModel(m) if m
          [result] # todo: Future refactor
      else
        Future.rejected(new Error('ModelRepo::getCachedCollectionModels is not applicable on server-side!'))


    invalidateCollectionCache: (name) ->
      if isBrowser
        @container.getService('localStorage').then (storage) =>
          storage.invalidateCollection(@constructor.__name, name)
      else
        Future.rejected(new Error('ModelRepo::invalidateCollectionCache is not applicable on server-side!'))


    _pathToObject: (pathList) ->
      result = {}
      for path in pathList
        changePointer = result
        parts = path.split('.')
        lastPart = parts.pop()
        # building structure based on dot-separated path
        for part in parts
          changePointer[part] = {}
          changePointer = changePointer[part]
        changePointer[lastPart] = true
      result


    _deepPick: (sourceObject, pattern) ->
      result = {}
      @_recursivePick(sourceObject, pattern, result)


    _recursivePick: (src, pattern, dst) ->
      for key, value of pattern
        if src[key] != undefined
          if value == true             # leaf of this branch
            dst[key] = src[key]
          else if _.isObject(src[key]) # value is object, diving deeper
            dst[key] = {}
            if @_recursivePick(src[key], value, dst[key]) == false
              return false
          else
            return false
        else
          return false
      dst


    _deepExtend: (args...) ->
      dst = args.shift()
      for src in args
        @_recursiveExtend(dst, src)
      dst


    _recursiveExtend: (dst, src) ->
      for key, value of src
        if value != undefined
          if dst[key] == undefined or _.isArray(value) or not _.isObject(dst[key])
            dst[key] = value
          else if _.isArray(value) or not _.isObject(value)
            dst[key] = value
          else
            @_recursiveExtend(dst[key], src[key])
      dst


    hasFieldCompareFunction: (field) ->
      ###
      Returns true if ModelRepo has custom compare function for the given field.
      ###
      @fieldCompareFunctions and @fieldCompareFunctions[field]


    fieldCompareFunction: (field, value1, value2) ->
      ###
      Executes and returnes result of custom compare function for the given field and values.
      ###
      @fieldCompareFunctions[field](value1, value2)


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @constructor.__name }#{ methodStr }"

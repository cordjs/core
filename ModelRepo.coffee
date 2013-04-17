define [
  'cord!Collection'
  'cord!Model'
  'cord!Module'
  'cord!isBrowser'
  'cord!utils/Defer'
  'cord!utils/Future'
  'underscore'
  'monologue' + (if document? then '' else '.js')
], (Collection, Model, Module, isBrowser, Defer, Future, _, Monologue) ->

  class ModelRepo extends Module
    @include Monologue.prototype

    model: Model

    _collections: null

    restResource: ''

    predefinedCollections: null

    fieldTags: null

    # key-value of available additional REST-API action names to inject into model instances as methods
    # key - action name
    # value - HTTP-method name in lower-case (get, post, put, delete)
    # @var Object[String -> String]
    actions: null


    constructor: (@container) ->
      throw new Error("'model' property should be set for the repository!") if not @model?
      @_collections = {}
      @_initPredefinedCollections()


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
      name = Collection.generateName(options)
      if @_collections[name]?
        collection = @_collections[name]
      else
        collection = new Collection(this, name, options)
        @_registerCollection(name, collection)
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


    buildSingleModel: (id, fields, syncMode, callback) ->
      ###
      Creates and syncs single-model collection by id and field list. In callback returns resulting model.
       Method returns single-model collection.

      :now sync mode is not available here since we need to return the resulting model.

      @param Integer id
      @param Array[String] fields list of fields names for the collection
      @param (optional)String syncMode desired sync and return mode, default to :cache
      @param Function(Model) callback
      @return Collection
      ###
      if _.isFunction(syncMode)
        callback = syncMode
        syncMode = ':cache'

      options =
        id: id
        fields: fields

      collection = @createCollection(options)
      collection.sync syncMode, ->
        callback(collection.get(id))
      collection


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
        throw new Error("Collection with name '#{ name }' is already registered in #{ @constructor.name }!")
      if not (collection instanceof Collection)
        throw new Error("Collection should be inherited from the base Collection class!")

      @_collections[name] = collection


    _fieldHasTag: (fieldName, tag) ->
      @fieldTags[fieldName]? and _.isArray(@fieldTags[fieldName]) and @fieldTags[fieldName].indexOf(tag) != -1


    # serialization related:

    toJSON: ->
      @_collections


    setCollections: (collections) ->
      @_collections = {}
      for name, info of collections
        collection = Collection.fromJSON(this, name, info)
        @_registerCollection(name, collection)


    # REST related

    query: (params, callback) ->
      resultPromise = Future.single()
      @container.eval 'api', (api) =>
        api.get @_buildApiRequestUrl(params), (response) =>
          result = []
          if _.isArray(response)
            result.push(@buildModel(item)) for item in response
          else
            result.push(@buildModel(response))
          callback?(result)
          resultPromise.resolve(result)
      resultPromise


    _buildApiRequestUrl: (params) ->
      urlParams = []
      if not params.id?
        urlParams.push("_filter=#{ params.filterId }") if params.filterId?
        urlParams.push("_sortby=#{ params.orderBy }") if params.orderBy?
        urlParams.push("_page=#{ params.page }") if params.page?
        urlParams.push("_pagesize=#{ params.pageSize }") if params.pageSize?
        # important! adding 1 to the params.end to compensate semantics:
        #   in the backend 'end' is meant as in javascript's Array.slice() - "not including"
        #   but in collection end is meant as the last index - "including"
        urlParams.push("_slice=#{ params.start },#{ params.end + 1 }") if params.start? or params.end?
        if params.filter
          for filterField of params.filter
            urlParams.push("#{ filterField }=#{ params.filter[filterField] }")

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

      @restResource + (if params.id? then ('/' + params.id) else '') + '/?' + urlParams.join('&')


    save: (model) ->
      ###
      Persists list of given models to the backend
      @param Model model model to save
      @return Future(response, error)
      ###
      promise = new Future(1)
      @container.eval 'api', (api) =>
        if model.id
          changeInfo = model.getChangedFields()
          changeInfo.id = model.id
          @emit 'change', changeInfo
          api.put @restResource + '/' + model.id, model.getChangedFields(), (response, error) =>
            if error
              @emit 'error', error
              promise.reject(error)
            else
              @cacheModel(model, model.getChangedFields())
              model.resetChangedFields()
              @emit 'sync', model
              promise.resolve(response)
        else
          api.post @restResource, model.getChangedFields(), (response, error) =>
            if error
              @emit 'error', error
              promise.reject(error)
            else
              @cacheModel(model, model.getChangedFields())
              model.id = response.id
              model.resetChangedFields()
              @emit 'sync', model
              @_suggestNewModelToCollections(model)
              @_injectActionMethods(model)
              promise.resolve(response)

      promise


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
      result = Future.single()
      @container.eval 'api', (api) =>
        apiParams = {}
        apiParams._pagesize = params.pageSize if params.pageSize?
        apiParams._sortby = params.orderBy if params.orderBy?
        apiParams._selectedId = params.selectedId if params.selectedId?
        apiParams._filter = params.filterId if params.filterId?
        if params.filter
          for filterField of params.filter
            apiParams[filterField]=params.filter[filterField]

        api.get @restResource + '/paging/', apiParams, (response) =>
          result.resolve(response)

      result


    emitModelChange: (model) ->
      if model instanceof Model
        changeInfo = model.toJSON()
        changeInfo.id = model.id
      else
        changeInfo = model
      @emit 'change', changeInfo


    callModelAction: (id, method, action, params) ->
      ###
      Request REST API action method for the given model
      @param Scalar id the model id
      @param String action the API action name on the model
      @param Object params additional key-value params for the action request (will be sent by POST)
      @return Future(response|error)
      ###
      result = new Future(1)
      @container.eval 'api', (api) =>
        api[method] "#{ @restResource }/#{ id }/#{ action }", params, (response, error) ->
          console.warn "callModelAction", response, error
          if error
            result.reject(error)
          else
            result.resolve(response)
      result


    buildModel: (attrs) ->
      ###
      Model factory.
      @param Object attrs key-value fields for the model, including the id (if exists)
      @return Model
      ###
      result = new @model(attrs)
      @_injectActionMethods(result) if attrs.id
      result


    _suggestNewModelToCollections: (model) ->
      ###
      Notifies all available collections to check if they need to refresh with the new model
      ###
      Defer.nextTick =>
        for name, collection of @_collections
          collection.checkNewModel(model)


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


    # local caching related

    getTtl: ->
      600


    cacheCollection: (collection, changedModels) ->
      name = collection.name
      result = new Future(1)
      if false and isBrowser
        require ['cord!cache/localStorage'], (storage) =>
          f = storage.saveCollectionInfo @constructor.name, name, collection.getTtl(),
            totalCount: collection._totalCount
            start: collection._loadedStart
            end: collection._loadedEnd
            hasLimits: collection._hasLimits
          result.when(f)

          ids = (m.id for m in collection.toArray())
          result.when storage.saveCollection(@constructor.name, name, ids)

          if not changedModels?
            changedModels = collection.toArray()
          for m in changedModels
            result.when @cacheModel(m)

          result.resolve()

          result.fail (error) ->
            console.error "cacheCollection failed: ", error
      else
        result.reject("ModelRepo::cacheCollection is not applicable on server-side!")

      result


    cacheModel: (model, changedFields) ->
      if false and isBrowser
        result = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          if not changedFields?
            changedFields = model.toJSON()
          ttl = if model.collection? then model.collection.getTtl() else @getTtl()

          save = (model) =>
            result.when storage.saveModel(@constructor.name, model.id, ttl + 10, model)

          storage.getModel(@constructor.name, model.id).done (m) =>
            save(@_deepExtend(m, changedFields))
          .fail ->
            save(changedFields)

        result
      else
        Future.rejected("ModelRepo::cacheModel is not applicable on server-side!")


    cutCachedCollection: (collection, loadedStart, loadedEnd) ->
      if false and isBrowser
        result = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          f = storage.saveCollectionInfo @constructor.name, collection.name, null,
            totalCount: collection._totalCount
            start: loadedStart
            end: loadedEnd
          result.when(f)
      else
        Future.rejected("ModelRepo::cutCachedCollection is not applicable on server-side!")


    getCachedCollectionInfo: (name) ->
      if false and isBrowser
        result = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          result.when storage.getCollectionInfo(@constructor.name, name)
        result
      else
        Future.rejected("ModelRepo::getCachedCollectionInfo is not applicable on server-side!")


    getCachedCollectionModels: (name, fields) ->
      if false and isBrowser
        resultPromise = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          storage.getCollection(@constructor.name, name).done (ids) =>
            fields = @_pathToObject(fields)
            result = []
            curPromise = new Future
            for id in ids
              break if curPromise.state() == 'rejected'
              prevPromise = curPromise
              curPromise = Future.single()
              do (id, prevPromise, curPromise) =>
                storage.getModel(@constructor.name, id).done (model) =>
                  prevPromise.done =>
                    m = @_deepPick(model, fields)
                    if m != false
                      m.id = id
                      result.push(@buildModel(m))
                      curPromise.resolve()
                    else
                      curPromise.reject("Not enough fields for model with id = #{ id } in the local storage!")
                  .fail (error) ->
                    curPromise.reject(error)
                .fail ->
                  curPromise.reject("Model with id = #{ id } was not found in local storage!")
            curPromise.done ->
              resultPromise.resolve(result)
            .fail (error) ->
              resultPromise.reject(error)
          .fail ->
            resultPromise.reject("Collection #{ name } is not found in local storage!")
        resultPromise
      else
        Future.rejected("ModelRepo::getCachedCollectionModels is not applicable on server-side!")


    getCachedModel: (id, fields) ->
      if false and isBrowser
        resultPromise = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          fields = @_pathToObject(fields)
          storage.getModel(@constructor.name, id).done (model) =>
            m = @_deepPick(model, fields)
            if m != false
              m.id = id
              resultPromise.resolve(m)
            else
              resultPromise.reject("Not enough fields for model with id = #{ id } in the local storage!")
          .fail ->
            resultPromise.reject("Model with id = #{ id } was not found in local storage!")
        resultPromise
      else
        Future.rejected("ModelRepo::getCachedModel is not applicable on server-side!")


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


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @constructor.name }#{ methodStr }"

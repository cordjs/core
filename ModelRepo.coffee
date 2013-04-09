define [
  'cord!Collection'
  'cord!Model'
  'cord!Module'
  'cord!utils/Defer'
  'cord!utils/Future'
  'underscore'
  'monologue' + (if document? then '' else '.js')
], (Collection, Model, Module, Defer, Future, _, Monologue) ->

  class ModelRepo extends Module
    @include Monologue.prototype

    model: Model

    _collections: null

    restResource: ''

    fieldTags: null

    # key-value of available additional REST-API action names to inject into model instances as methods
    # key - action name
    # value - HTTP-method name in lower-case (get, post, put, delete)
    # @var Object[String -> String]
    actions: null


    constructor: (@container) ->
      throw new Error("'model' property should be set for the repository!") if not @model?
      @_collections = {}


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
      for name, info of collections
        collection = Collection.fromJSON(this, name, info)
        @_registerCollection(name, collection)


    # REST related

    query: (params, callback) ->
      @container.eval 'api', (api) =>
        api.get @_buildApiRequestUrl(params), (response) =>
          result = []
          if _.isArray(response)
            result.push(@buildModel(item)) for item in response
          else
            result.push(@buildModel(response))
          callback(result)


    _buildApiRequestUrl: (params) ->
      #apiRequestUrl = 'discuss/?_sortby=-timeUpdated&_page=1&_pagesize=50&_fields=owner.id,subject,content&_calc=commentsStat,accessRights'
      #apiRequestUrl = 'discuss/' + talkId + '/?_fields=subject,content,timeCreated,owner.id,userCreated.employee.name,userCreated.employee.smallPhoto,participants.employee.id,attaches&_calc=accessRights'
      urlParams = []
      if not params.id?
        urlParams.push("_filter=#{ params.filterId }") if params.filterId?
        urlParams.push("_sortby=#{ params.orderBy }") if params.orderBy?
        urlParams.push("_page=#{ params.page }") if params.page?
        urlParams.push("_pagesize=#{ params.pageSize }") if params.pageSize?
        urlParams.push("_slice=#{ params.start },#{ params.end }") if params.start? or params.end?

      commonFields = []
      calcFields = []
      for field in params.fields
        if @_fieldHasTag(field, ':backendCalc')
          calcFields.push(field)
        else
          commonFields.push(field)
      urlParams.push("_fields=#{ commonFields.join(',') }")
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
              model.resetChangedFields()
              @emit 'sync', model
              promise.resolve(response)
        else
          api.post @restResource, model.getChangedFields(), (response, error) =>
            if error
              @emit 'error', error
              promise.reject(error)
            else
              model.id = response.id
              model.resetChangedFields()
              @emit 'sync', model
              @_suggestNewModelToCollections(model)
              @_injectActionMethods(model)
              promise.resolve(response)
      promise


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


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @constructor.name }#{ methodStr }"

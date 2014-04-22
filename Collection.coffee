define [
  'cord!isBrowser'
  'cord!Module'
  'cord!utils/Defer'
  'cord!utils/Future'
  'monologue' + (if document? then '' else '.js')
  'underscore'
], (isBrowser, Module, Defer, Future, Monologue, _) ->

  class ModelNotExists extends Error

    constructor: (@message) ->
      @name = 'ModelNotExists'


  class Collection extends Module
    @include Monologue.prototype

    @__name: 'Collection' # obfuscation support

    _filterType: ':none' # :none | :local | :backend
    _filterId: null
    _filterParams: null # params for filter
    _filterFunction: null

    _orderBy: null
    _fields: null

    # correctly ordered list of models of the collection
    _models: null

    # cached total (not only loaded) count of models in this collection
    _totalCount: null
    _cacheLoaded: false
    _totalCountFromCache: false

    # index of models by id
    _byId: null

    _initialized: false

    # partially loaded collection properties
    _loadedStart: 4294967295
    _loadedEnd: -1

    _hasLimits: null
    _requestParams: null
    _queryQueue: null

    # helper value for event propagation optimization
    _selfEmittedChangeModelId: null

    # custom rest access point
    _accessPoint: null
    
    #Last time collection was queried from backend
    _lastQueryTime: 0


    @generateName: (options) ->
      ###
      Generates and returns unique "checksum" name of a collection depending only of the given options.
       This allows to reuse collections with the totally same options instead of duplicating them.
      @param Object options same options, that will be passed to the collection constructor
      @return String
      ###
      accessPoint = options.accessPoint ? ''
      orderBy = options.orderBy ? ''
      filterId = options.filterId ? ''
      filterParams = options.filterParams ? ''
      filterParams = filterParams.join(',') if _.isArray(filterParams)
      filter = _.reduce options.filter , (memo, value, index) ->
        memo + index + '_' + value
      , ''

      if options.requestParams
        requestOptions = _.reduce options.requestParams, (memo, value, index) ->
          memo + index + '_' + value
        , ''
      else
        requestOptions = '';

      clazz = if options.collectionClass? then options.collectionClass.__name else ''
      fields = options.fields ? []
      calc = options.calc ? []
      id = options.id ? 0
      pageSize = if options.pageSize then options.pageSize else ''

      collectionVersion = global.config.static.collection

      [
        collectionVersion
        clazz
        accessPoint
        fields.sort().join(',')
        calc.sort().join(',')
        filterId
        filterParams
        filter
        orderBy
        id
        requestOptions
        pageSize
      ].join('|').replace(/\:/g, '')


    constructor: (@repo, @name, options) ->
      ###
      @param ModelRepo repo model repository to which the collection belongs
      @param String name unique name of the collection in the model repository
      @param Object options collection filtering, ordering and field fetching options
      ###
      @_models = []
      @_byId = {}
      @_filterType = options.filterType ? ':backend'
      @_fields = options.fields ? []
      @_reconnect = options.reconnect ? false

      if options.model
        @_fillModelList [options.model]
        @_orderBy = options.orderBy ? null
        @_filterId = null
        @_filterParams = null
        @_id = options.model.id
        @_filter = {}
      else
        @_orderBy = options.orderBy ? null
        @_filterId = options.filterId ? null
        @_filterParams = options.filterParams ? null
        @_id = options.id ? 0
        @_filter = options.filter ? {}
        @_pageSize = options.pageSize ? 0

      #special case - fixed collections, when model are already provided and we have no need to do anything with them
      if options.fixed && options.models
        @_fixed = true
        @_byId = options.models
        @_models = _.values options.models

      @_requestParams = options.requestParams ? {}

      @_queryQueue =
        loadingStart: @_loadedStart
        loadingEnd: @_loadedEnd
        list: []

      @_accessPoint = options.accessPoint ? null

      # subscribe for model changes to smart-proxy them to the collections model instances
      @repo.on('change', @_handleModelChange).withContext(this)


    cache: ->
      ###
      Cache collection
      ###
      @repo.cacheCollection @


    invalidateCache: ->
      ###
      Invalidtes collection's cache.
      Call in case of an emergency!
      Returns promise
      ###
      #@_totalCount = null #force getPagingInfo to make request
      @repo.invalidateCollectionCache(@name)


    isConsistent: (array) ->
      ###
        Return true if collection or array has no gaps
      ###

      if !array
        if @_loadedStart > @_loadedEnd and @_models.length > 0
          return false

        modelsEnd = @_models.length - 1
        lastIndex = if modelsEnd < @_loadedEnd then modelsEnd else @_loadedEnd

        if lastIndex >= 0
          for i in [@_loadedStart..lastIndex]
            if @_models[i] == undefined
              return false
      else
        for model in array
          if model == undefined
            return false

      return true
      
    getLastQueryTime: ->
      if @_lastQueryTime then @_lastQueryTime else 0
      
    
    getLastQueryTimeDiff: ->
      (new Date).getTime() - @getLastQueryTime()


    sync: (returnMode, start, end, callback) ->
      ###
      Initiates synchronization of the collection with some backend; fires callback and completes resulting future
       denending of given return mode.
      It's possible to call method:
       * without any arguments - whole range in :sync mode, completion by returning future.
       * without first three arguments - the same but with callback
       * without start and end arguments - whole range in the given mode
       * returnMode must be provided if it's necessary to pass range options (start and end).
       * start and end must be passed either both or none
      @param (optional) String returnMode :sync -  return only after sync with server
                                          :async - return immidiately if collection is initialized before,
                                                   sync in background
                                          :now -   return immidiately even if collection is not ever syncronized before,
                                                   sync in background
                                          :cache - return cached collection if initialized (without syncing),
                                                   or perform like :sync otherwise
      @param (optional)Int start starting position of the required range
      @param (optional)Int end ending position of the required range
      @param (optional)Function(this) callback callback to call on sync completion depending on the return mode.
      @return Future(this)
      ###
      if _.isFunction(returnMode)
        callback = returnMode
        returnMode = ':sync'
        start = end = undefined
      else if _.isFunction(start)
        callback = start
        start = end = undefined
      returnMode = ':cache' if returnMode == ':cache-async'
      returnMode ?= ':sync'
      cacheMode = (returnMode == ':cache')

      # Special case - fixed collection
      if @_fixed
        resultPromise = Future.single('Collection::sync resultPromise')
        resultPromise.resolve(this)
        callback?(this)
        return resultPromise

      # this future is resolved by cache results or server results - which come first
      firstResultPromise = Future.single('Collection::sync firstResultPromise')
      # we should wait for range information from the local cache before staring remote sync query
      rangeAdjustPromise = Future.single('Collection::sync rangeAdjustPromise')
      # special promise for cache mode to avoid running remote sync if unnecessary
      activateSyncPromise = Future.single('Collection::sync activateSyncPromise')
      activateSyncPromise.resolve() if not cacheMode

      if not @_initialized
        # try to load local storage cache only when syncing first time
        @_getModelsFromLocalCache(start, end, rangeAdjustPromise).done (models, syncStart, syncEnd) =>
          Defer.nextTick => # give remote sync a chance
            if not firstResultPromise.completed()
              @_fillModelList(models, syncStart, syncEnd) if not @_initialized # the check is need in case of parallel cache trial
              firstResultPromise.resolve(this)
          activateSyncPromise.reject() if cacheMode # remote sync is not necessary in :cache mode
        .fail (error) =>
          activateSyncPromise.resolve() if cacheMode # cache failed, need to remote sync even in :cache mode
      else # if @_initialized
        rangeAdjustPromise.resolve(start, end)
        if cacheMode
          # in :cache mode we need to check if requested range is already loaded into the collection's payload
          if start? and end?
            if start >= @_loadedStart and end <= @_loadedEnd
              activateSyncPromise.reject()
              firstResultPromise.resolve(this)
            else
              activateSyncPromise.resolve()
          else
            if @_hasLimits == false
              activateSyncPromise.reject()
              firstResultPromise.resolve(this)
            else
              activateSyncPromise.resolve()

      # sync with backend
      syncPromise = Future.single('Collection::sync syncPromise ' + @_accessPoint + ' ' + JSON.stringify(@_filter) + ' ' + @_fields) # special promise for :sync mode completion
      activateSyncPromise.done => # pass :cache mode
        rangeAdjustPromise.done (syncStart, syncEnd) => # wait for range adjustment from the local cache
          @_enqueueQuery(syncStart, syncEnd).done => # avoid repeated refresh-query
            syncPromise.resolve(this)
            if not firstResultPromise.completed()
              firstResultPromise.resolve(this)
          .fail ->
            syncPromise.reject()

      # handling different behaviours of return modes
      resultPromise = Future.single('Collection::sync resultPromise')
      switch returnMode
        when ':sync' then resultPromise.when(syncPromise)
        when ':async'
          if start? and end?
            if start >= @_loadedStart and end <= @_loadedEnd
              resultPromise.resolve(this)
            else
              resultPromise.when(firstResultPromise)
          else
            if @_hasLimits == false
              resultPromise.resolve(this)
            else
              resultPromise.when(firstResultPromise)
        when ':now' then resultPromise.resolve(this)
        when ':cache' then resultPromise.when(firstResultPromise)

      resultPromise.done =>
        callback?(this)


    scanModels: (scannedFields, searchedText, limit) ->
      ###
      Scans models in current collection for searched Text in scannedFields and return object of their clones
      @param Array scannedFields - fields to be scanned
      @param String searchedText - searched text
      @return object { <id>: <model>, ... }
      ###
      result = {}
      return result if !searchedText
      amount = 0
      searchedText = searchedText.toLowerCase()

      for model in @_models
        for fieldName in scannedFields
          if model[fieldName] && !result[model.id] && String(model[fieldName]).toLowerCase().indexOf(searchedText) > -1
            result[model.id] = _.clone model
            break
        if limit && amount >= limit
          break
      result


    have: (id) ->
      !!@_byId[id]


    get: (id) ->
      if @_byId[id]?
        @_byId[id]
      else
        throw new ModelNotExists("There is no model with id = #{ id } in collection [#{ @debug() }]!")


    toArray: ->
      @_models


    isInitialized: ->
      ###
      Indicates that the collection is already synchronized at least once.
      @return Boolean
      ###
      @_initialized


    checkExistingModel: (model) ->
      #Refresh the collection only if it contains suggested model
      id = if _.isObject(model) then model.id else model

      if id && @_byId[id]
        @refresh()


    checkNewModel: (model, emitModelChangeExcept = true) ->
      ###
      Checks if the new model is related to this collection. If it is reloads collection from the backend.
      @param Model model the new model
      ###
      @refresh(model.id, emitModelChangeExcept) if not @_id or @_id == model.id


    _reorderModelsLocal: ->
      ###
      Rearrange collection models according to the orderBy options.
      ###
      if @_orderBy? and @_orderBy != ''
        iterator = @_orderBy
      else if @constructor.orderBy? and @constructor.orderBy != ''
        iterator = @constructor.orderBy
      else
        return

      sortDesc = false

      if _.isString(iterator)
        first = iterator.substr(0, 1)
        sortDesc = (first == '-')
        iterator = iterator.substr(1) if first == '-' or first == '+'
      else
        sortDesc = true if @constructor.orderDir == ':desc'

      @_models = _.sortBy(@_models, iterator)
      @_models.reverse() if sortDesc


    _reindexModels: ->
      ###
      Rebuilds useful index of the models by their id.
      ###
      @_byId = {}
      for m in @_models
        if m != undefined
          @_byId[m.id] = m


    refresh: (currentId, emitModelChangeExcept = true) ->
      ###
      Reloads currently loaded part of collection from the backend.
      By the way triggers change events for every changed model and for the collection if there are any changes.
      todo: support of single-model collections
      @param int currentId - id of currently used model (selected or showed),
      if currentId and pageSize are defined, refresh will start from page, containing the currentId model, going up and down
      ###

      #Special case - fixed collections, no need to sync or refresh
      return if @_fixed

      return if @_refreshInProgress

      @_refreshInProgress = true

      #Refresh all models at once if no paging used
      if not @_pageSize
        queryParams = @_buildRefreshQueryParams()
        @repo.query queryParams, (models) =>
          @_replaceModelList models, queryParams.start, queryParams.end, emitModelChangeExcept
          @_refreshInProgress = false
          #TODO: GC unregister single model collection if it became empty.
      else
        #refresh paging info first

        #Find current model page
        if currentId && @_byId[currentId]
          modelIndex = _.indexOf @_models, @_byId[currentId]
          modelPage = Math.ceil(modelIndex + 1/ @_pageSize)

        @getPagingInfo(currentId, true).done (paging) =>
          #Don't refresh collection if currentId is not belonged to it
          if !currentId || paging.selectedPage > 0 || modelIndex > -1
            startPage = if paging.selectedPage > 0 then paging.selectedPage else 1
            #refresh pages, starting from current, and then go 1 up, 1 down, etc
            #if modelPage didn't change refresh only page, containing the model
            direction = 'down'
            if currentId && modelPage && modelPage == paging.selectedPage
              direction = 'stop'

            @_topPage = @_bottomPage = startPage
            @_refreshReachedTop = false
            @_refreshReachedBottom = false
            @_refreshPage startPage, paging, direction
          else
            @_refreshInProgress = false


    _refreshPage: (page, paging, direction) ->
      if paging.pages == 0
      # special case, when collection nullifies on server
        @_refreshInProgress = false
        return @_replaceModelList [], @_loadedStart, @_loadedEnd
      if page > 0 && page <= paging.pages
        start = (page - 1) * @_pageSize
        end = page * @_pageSize - 1
        @_enqueueQuery(start, end, true).done =>

          if direction == 'stop'
            @_refreshInProgress = false
            return

          if !@_refreshReachedTop
            @_refreshReachedTop = page == 1

          if !@_refreshReachedBottom
            @_refreshReachedBottom = page == paging.pages

          if @_refreshReachedTop
            direction = 'down'
          else if @_refreshReachedBottom
            direction = 'up'
          else
            direction = if direction == 'up' then 'down' else 'up'

          if direction == 'up'
            page = @_topPage = @_topPage - 1
          else
            page = @_bottomPage = @_bottomPage + 1

          @_refreshPage page, paging, direction
      else
        @_refreshInProgress = false


    _buildRefreshQueryParams: ->
      ###
      Builds backend query params for the currently defined collection params to refresh collection items.
      @return Object key-value params for the ModelRepo::query() method
      ###
      if @_id
        result =
          id: @_id
          fields: @_fields
          requestParams: @_requestParams
          accessPoint: @_accessPoint
          orderBy: @_orderBy
      else
        result =
          orderBy: @_orderBy
          fields: @_fields
          filter: @_filter
          requestParams: @_requestParams
          accessPoint: @_accessPoint
        if @_filterType == ':backend'
          result.filterId = @_filterId
          result.filterParams = @_filterParams
        if @_hasLimits
          result.start = @_loadedStart
          result.end = @_loadedEnd
      result


    addModel: (model, position = ':tail') ->
      ###
      Manually adds model into the collection and reorders the list of the models.
      Emits 'change' event for the collection.
      @param Model model the new or updated model
      @param String position ':head' or ':tail' append
      ###
      position = ':tail' if position != ':head'
      model.setCollection(this)
      @_models = _.without(@_models, @_byId[model.id]) if @_byId[model.id]?
      if position == ':tail'
        @_models.push(model)
      else
        @_models.unshift(model)
      @_reorderModelsLocal()
      @_byId[model.id] = model

      #calculate model's page
      modelPage = 0
      if !isNaN(parseInt(@_pageSize)) && @_pageSize > 0
        modelIndex = _.indexOf @_models, model
        modelPage = Math.ceil(modelIndex + 1/ @_pageSize)

      changedModels = {}
      changedModels[model.id] = model

      @emit 'change', {firstPage: modelPage, lastPage: modelPage, models: changedModels}


    _fillModelList: (models, start, end) ->
      ###
      Fills model list with initial data.
      Differs from _replaceModelList() in behaviour of firing change events for models and collection. This method
       doesn't fire any events. Therefore it should be used only for initial filling.
      @param Array[Model] models list of models
      @param (optional)Int start starting index of the loading range
      @param (optional)Int end ending index of the loading range
      ###
      if start? and end?
        # appending new models to the collection according to the paging options
        for model, i in models
          if model
            model.setCollection(this)
            @_models[start + i] = model

        @_loadedStart = start if start < @_loadedStart
        @_loadedEnd = end if end > @_loadedEnd

        @_hasLimits = (@_hasLimits != false)
      else
        @_models = models
        @_loadedStart = 0
        @_loadedEnd = if models.length == 0 then 0 else models.length - 1
        @_hasLimits = false
        @_totalCount = models.length

        model.setCollection(this) for model in @_models

      @_reindexModels()
      @_initialized = true


    _replaceModelList: (newList, start, end, emitModelChangeExcept = true) ->
      ###
      Substitutes part of list of models with the new ones comparing them by the way and triggering according events.
      If start and end arguments are not given, then the whole list is replaced starting from index 0.
      @param Array[Model] newList list of new models
      @param (optional)Int start starting index of the destination list, from which should replacement started
      @param (optional)Int end index of last item to replace
      ###

      # This means that previously collection was empty and something new has arrived

      oldListCount = @_models.length
      oldList = _.clone(@_models)

      if (start? and end?) and (start < end)
        ###
        #in case of refreshing, we'll just replace the list
        if start == @_loadedStart && end == @_loadedEnd
          @_fillModelList newList
          return true
        ###

        loadingStart = start
        loadingEnd = end
        @_models = _.clone(@_models)
      else
        loadingStart = 0
        loadingEnd = newList.length - 1
        @_models = []

      firstChangedIndex = oldListCount
      lastChangedIndex = 0

      deleted = false
      deletedModels = {}
      changed = false
      changedModels = {}

      newListIds = {}
      for item in newList
        newListIds[item.id] = item

      for model in oldList
        # Бывает так, что в списке моделей есть пропуски... Надо с этим разобраться.
        continue if not model
        if not newListIds[model.id]
          deletedModels[model.id] = model
          deleted = true
          changed = true

      targetIndex = loadingStart - 1

      # appending/replacing new models to the collection according to the paging options
      for model, i in newList
        model.setCollection(this)
        targetIndex = loadingStart + i
        if @_byId[model.id]? and @_compareModels(model, @_byId[model.id])
          changed = true
          firstChangedIndex = targetIndex if targetIndex < firstChangedIndex
          lastChangedIndex  = targetIndex if targetIndex > lastChangedIndex
          changedModels[model.id] = model
          @emit "model.#{ model.id }.change", model
          @emitModelChangeExcept(model) if emitModelChangeExcept

        if not oldList[targetIndex]? or model.id != oldList[targetIndex].id
          changed = true
          changedModels[model.id] = model
          firstChangedIndex = targetIndex if targetIndex < firstChangedIndex
          lastChangedIndex  = targetIndex if targetIndex > lastChangedIndex

        @_models[targetIndex] = model

      if targetIndex < loadingEnd
        @_models.splice(targetIndex + 1, loadingEnd - targetIndex)

      @_loadedStart = loadingStart if loadingStart < @_loadedStart
      if loadingEnd > @_loadedEnd
        @_loadedEnd = loadingEnd
      else if loadingEnd =-1 and @_loadedEnd == -1
        @_loadedEnd = 0

      @_reindexModels()
      @_initialized = true

      # in situation when newList is empty, we must emit change event
      if newList.length < oldListCount
        changed = true
        firstChangedIndex = newList.length if newList.length < firstChangedIndex
        lastChangedIndex  = oldListCount if oldListCount > lastChangedIndex

      firstPage = 0
      lastPage  = 0
      if !isNaN(parseInt(@_pageSize)) && @_pageSize > 0
        firstPage = Math.ceil((firstChangedIndex + 1) / @_pageSize)
        lastPage = Math.ceil((lastChangedIndex + 1) / @_pageSize)

      @emit 'change', {firstPage: firstPage, lastPage: lastPage, models: changedModels} if changed
      @emit 'delete', {models: deletedModels} if deleted

      if not (start? and end?)
        @_totalCount = newList.length
      else if changed
        @_totalCount = null # should be asked from the backend again just in case

      @repo.cacheCollection(this)


    _compareModels: (model1, model2) ->
      ###
      Deeply compares two models using only fields of this collection.
      @param Model model1
      @param Model model2
      @return Boolean true if models differ, false if they are the same
      ###
      return true if model1.id != model2.id
      for field in model1.getDefinedFieldNames()
        if field != 'id' and not @_modelsEq(model1[field], model2[field])
          return true
      return false


    _modelsEq: (a, b) ->
      ###
      Port of underscore's isEqual (to be more precise, eq) function with cutted down support of recursive structures
       and cutted down checking of fields in b that doesn't exists in a.
      ###

      # Undefined models are never equal
      return false if a == undefined || b == undefined

      # Identical objects are equal. `0 === -0`, but they aren't identical.
      # See the Harmony `egal` proposal: http://wiki.ecmascript.org/doku.php?id=harmony:egal.
      return a != 0 || 1 / a == 1 / b if a == b
      # A strict comparison is necessary because `null == undefined`.
      return a == b if a == null || b == null
      # Unwrap any wrapped objects.
      a = a._wrapped if a._chain
      b = b._wrapped if b._chain
      # Invoke a custom `isEqual` method if one is provided.
      return a.isEqual(b) if a.isEqual && _.isFunction(a.isEqual)
      return b.isEqual(a) if b.isEqual && _.isFunction(b.isEqual)
      # Compare `[[Class]]` names.
      className = toString.call(a)
      return false if className != toString.call(b)
      switch className
        # Strings, numbers, dates, and booleans are compared by value.
        when '[object String]'
          # Primitives and their corresponding object wrappers are equivalent; thus, `"5"` is
          # equivalent to `new String("5")`.
          return a == String(b)
        when '[object Number]'
          # `NaN`s are equivalent, but non-reflexive. An `egal` comparison is performed for
          # other numeric values.
          return a != +a ? b != +b : (a == 0 ? 1 / a == 1 / b : a == +b)
        when '[object Date]', '[object Boolean]'
          # Coerce dates and booleans to numeric primitive values. Dates are compared by their
          # millisecond representations. Note that invalid dates with millisecond representations
          # of `NaN` are not equivalent.
          return +a == +b;
        # RegExps are compared by their source patterns and flags.
        when '[object RegExp]'
          return a.source == b.source && \
                 a.global == b.global && \
                 a.multiline == b.multiline && \
                 a.ignoreCase == b.ignoreCase

      return false if (typeof a != 'object' || typeof b != 'object')

      size = 0
      result = true
      # Recursively compare objects and arrays.
      if className == '[object Array]'
        # Compare array lengths to determine if a deep comparison is necessary.
        size = a.length
        result = (size == b.length)
        if result
          # Deep compare the contents, ignoring non-numeric properties.
          while size--
            # Ensure commutative equality for sparse arrays.
            if !(result = size in a == size in b && @_modelsEq(a[size], b[size]))
              break
      else
        # Objects with different constructors are not equivalent.
        return false if 'constructor' in a != 'constructor' in b || a.constructor != b.constructor
        # Deep compare objects.
        for key of a
          if _.has(a, key)
            # Count the expected number of properties.
            size++
            # Deep compare each member.
            # Ignore properties from b which a does not contain
            if _.has(b, key) && !(result = @_modelsEq(a[key], b[key]))
              break
      result


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
        continue if dst[key] == undefined

        if _.isArray(val) and _.isArray(dst[key])
          if val.length == 0
            #If dst was an array longer than 0
            result = (!_.isArray(dst[key])) || dst[key].length > 0
            dst[key] = []
          else
            if _.isArray dst[key]
              for newVal,newKey in val
                result |= dst[key][newKey] == undefined || @_recursiveCompare(newVal, dst[key][newKey])
                if result
                  dst[key] = _.clone(val)
                  break
            else
              dst[key] = _.clone(val)
              result = true

        # todo: can be more smart here, but very difficult
        else if _.isObject(val) and _.isObject(dst[key])
          result = @_recursiveCompareAndChange(val, dst[key])

        else if typeof val == typeof dst[key] and not _.isEqual(val, dst[key])
          dst[key] = _.clone(val)
          result = true

      result


    _recursiveCompare: (src, dst) ->
      ###
      Does the same as _recursiveCompareAndChange, but without actual changing the values
      Also _recursiveCompareAndChange uses this function itself.
      ###

      result = false

      for key, val of src
        if dst[key] != undefined
          if _.isArray(val)
            if val.length == 0
              #If dst was an array longer than 0
              result = (!_.isArray(dst[key])) || dst[key].length > 0
            else
              if _.isArray dst[key]
                for newVal,newKey in val
                  result |= @_recursiveCompare(newVal, dst[key][newKey])
                  if result
                    break
              else
                result = true
            # todo: can be more smart here, but very difficult
          else if not _.isObject(val)
            if not _.isEqual(val, dst[key])
              result = true
          else if @_recursiveCompareAndChange(val, dst[key])
            result = true
        if result
          break

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

    getPage: (firstPage, lastPage) ->
      ###
      Obtains and returns in future portion of models of the collection according to given paging params
      If the second argument is omitted than only one page is returned.
      Page size could be set on collection construction via pageSize parameter (default = 50)
      @param Int firstPage number of the first page
      @param (optional)Int lastPage number of the last page
      @return Future(Array[Model])
      ###
      if arguments.length == 1
        lastPage = firstPage

      if firstPage
        start = (firstPage - 1) * @_pageSize
        end = start + @_pageSize * (lastPage - firstPage + 1) - 1 if lastPage
      else
        start = end = null

      slice = =>
        if start? and end?
          @toArray().slice(start, end + 1)
        else
          @toArray()

      promise = Future.single('Collection::getPage')

      #sometimes collection could be toren apart, check for this case
      if @_loadedStart <= start and (@_loadedEnd >= end || @_totalCount == @_loadedEnd + 1) and @isConsistent((sliced = slice())) == true
        promise.resolve(sliced)
      else
        @sync ':async', start, end, =>
          promise.resolve(slice())
      promise


    getPagingInfo: (selectedId, refresh) ->
      ###
      Returns paging information for this collection based on given page size and optional selected model's id.
      Uses cached value of total models count to calculate paging locally and avoid backend hits.
      pagesize could be defined on collection construction, via pageSize parameter (default is 50)
      @param (optional) Scalar selectedId id of the selected model
      @param (optional) bool refresh - ignore cache settings, refresh info from backend
      @return Future(Object)
                total: Int (total count this collection's models)
                pages: Int (total number of pages)
                selected: Int (0-based index/position of the selected model)
                selectedPage: Int (1-based number of the page that contains the selected model)
      ###
      result = Future.single('Collection::getPagingInfo')

      cachePromise = Future.single('Collection::getPagingInfo cachePromise')
      if !@isInitialized() || @_cacheLoaded || not isBrowser || refresh
        cachePromise.resolve()
      else
        @_cacheLoaded = true
        @repo.getCachedCollectionInfo(@name).done (info) =>
          @_totalCount = info.totalCount
          @_totalCountFromCache = true
          cachePromise.resolve()
        .fail ->
          cachePromise.resolve()

      cachePromise.done =>
        localCalculated = false
        if @_totalCount? && @_totalCount > 0
          if selectedId
            if (m = @_byId[selectedId])?
              index = @_models.indexOf(m)
              result.resolve
                total: @_totalCount
                pages: Math.ceil(@_totalCount / @_pageSize)
                selected: index
                selectedPage: Math.ceil((index + 1) / @_pageSize)
              localCalculated = true
          else
            result.resolve
              total: @_totalCount
              pages: Math.ceil(@_totalCount / @_pageSize)
            localCalculated = true

        if not localCalculated
          params =
            pageSize: @_pageSize
            orderBy: @_orderBy
          params.selectedId = selectedId if selectedId
          if @_filterType == ':backend'
            params.filterId = @_filterId
            params.filterParams = @_filterParams if @_filterParams

          params.filter = @_filter if @_filter

          @repo.paging(params).done (response) =>
            @_totalCount = if response then response.total else response
            #special case: collections with zero amount of model will be never initialized otherwize
            if @_totalCount == 0
              #mark this collection as initialized, if it's empty
              @_loadedStart = 0
              @_loadedEnd = @_pageSize - 1
              @_initialized = true
            if response
              result.resolve(response)
            else
              result.resolve({})

      result

    updateLastQueryTime: ->
      @_lastQueryTime = (new Date()).getTime()
      

    _enqueueQuery: (start, end, refresh) ->
      ###
      Adds new query to the model repository to the queue and returns the future which is completed when the query is
       is completed and results are filled into collection.
      If there is query or queries in the queue, which covers requested range of models, than the last covering
       query's future is returned and no queries are added to the queue.
      If start or end isn't defined, than the whole range of models of the type are loaded from the repository.
      @param Int start starting position or range required to load
      @param Int end ending position or range required to load
      @return Future()
      ###

      # detecting query type and adjusting range to request according to the already requested range
      curLoadingStart = @_queryQueue.loadingStart
      curLoadingEnd = @_queryQueue.loadingEnd
      if refresh
        queryType = 'replace'
      else
        if @_hasLimits != false and start? and end?
          if start < curLoadingStart and end < curLoadingStart and start < curLoadingEnd
            queryType = 'prepend'
            end = curLoadingStart - 1
          else if end > curLoadingEnd and start > curLoadingEnd and end > curLoadingStart
            queryType = 'append'
            start = curLoadingEnd + 1
          else
            queryType = 'replace'
            start = (if start < curLoadingStart then start else curLoadingStart)
            end = (if end > curLoadingEnd then end else curLoadingEnd)

          @_queryQueue.loadingStart = if start < curLoadingStart then start else curLoadingStart
          @_queryQueue.loadingEnd = if end > curLoadingEnd then end else curLoadingEnd
        else
          queryType = 'all'
          @_queryQueue.loadingStart = start = undefined
          @_queryQueue.loadingEnd = end = undefined

      if ( not end? || (end - start > 50) ) && not @_id && not @repo._debugCanDoUnlimit
        _console.error 'ACHTUNG!!! Me bumped into unlimited query: end =', end, 'start =', start, @repo.restResource
        
      # detecting if there are queries in the queue which already cover required range
      curStart = start
      curEnd = end
      waitForQuery = null
      queryList = @_queryQueue.list
      for info in queryList
        if info.start? and info.end?
          if start? and end?
            if curStart >= info.start and curStart <= info.end
              curStart = info.end + 1
            if curEnd >= info.start and curEnd <= info.end
              curEnd = info.start - 1
            if curStart > curEnd
              waitForQuery = info
              break
          else
            continue
        else
          waitForQuery = info
          break

      # if not covered by the already queued queries, adding a new query to the queue
      if not waitForQuery?
        queryPromise = Future.single('Collection::_enqueueQuery queryPromise')
        waitForQuery =
          start: start
          end: end
          type: queryType
          promise: queryPromise

        # attaching to the last query's in the queue promise
        if (lastQuery = _.last(queryList))?
          prevQueryPromise = lastQuery.promise
        else
          prevQueryPromise = new Future('Collection::_enqueueQuery prevQueryPromise')

        queryList.push(waitForQuery)

        # starting to process query only after completion of the previous in the queue
        prevQueryPromise.done =>
          queryParams =
            fields: @_fields
            reconnect: @_reconnect

          queryParams.orderBy = @_orderBy

          if @_id
            queryParams.id = @_id
          else
            if @_filterType == ':backend'
              queryParams.filterId = @_filterId
              queryParams.filterParams = @_filterParams if @_filterParams

            queryParams.filter = @_filter if @_filter
            queryParams.start = start if start?
            queryParams.end = end  if end?

          queryParams.requestParams = @_requestParams if @_requestParams
          queryParams.accessPoint = @_accessPoint if @_accessPoint

          @updateLastQueryTime()

          @repo.query(queryParams).done (models) =>
            # invalidating cached totalCount
            if @_totalCountFromCache
              @_totalCount = null
              @_totalCountFromCache = false

            if (start >= @_loadedStart and start <= @_loadedEnd) or (end >= @_loadedStart and end <= @_loadedEnd) or (start == undefined and end == undefined and @_loadedEnd > -1)
              # if there are interceptions of the just loaded set and already existing set,
              #  than we need to trigger events
              @_replaceModelList models, start, end
            else
              # append or prepend - not triggering events
              @_fillModelList models, start, end
              @repo.cacheCollection(this)

            @_initialized = true

            # not forgetting to remove the completed query from the queue
            if queryList[0] == waitForQuery
              queryList.shift()
            else
              throw new Error("Inconsistent query queue: #{ queryList }, #{ waitForQuery }!")

            queryPromise.resolve()

      waitForQuery.promise


    # local cache related

    getTtl: ->
      300


    _adjustLocalCacheRange: (targetStart, targetEnd, loadedStart, loadedEnd) ->
      ###
      Smartly adjusts range of the local stored models to the reasonable amount.
      Takes into account only 6 pages around the requested one, all models beyond that are considered as not saved.
      @param Int targetStart target range start
      @param Int targetEnd target range end
      @param Int loadedStart cached range start
      @param Int lodedEnd cached range end
      @return [Int, Int] tuple of adjusted start and end position
      ###
      base = targetEnd - targetStart + 1
      before = Math.floor((targetStart - loadedStart) / base)
      after = Math.floor((loadedEnd - targetEnd) / base)
      if before + after > 6
        if before < after
          before = Math.min(before, 3)
          after = 6 - before
        else
          after = Math.min(after, 3)
          before = 6 - after

      resultStart = targetStart - before * base
      resultEnd = targetEnd + after * base

      [resultStart, resultEnd]


    _getModelsFromLocalCache: (start, end, rangeAdjustPromise) ->
      ###
      Tries to load given range of models from the browser's local storage.
      @param Int start required range starting position
      @param Int end required range ending position
      @param Future(Int, Int) rangeAdjustPromise future that should be completed when loading from cache range info
                                                 is calculated
      @return Future(models, start, end) future completed with list of models created from cache and resulting range
      ###
      # avoiding repeated cache request (in case of async cache backend)
      if not @_firstGetModelsFromCachePromise
        @_firstGetModelsFromCachePromise = Future.single('Collection::_getModelsFromLocalCache')
        @_firstRangeAdjustPromise = rangeAdjustPromise
        # getting cached range information at first
        @repo.getCachedCollectionInfo(@name).done (info) =>
          syncStart = start
          syncEnd = end
          loadLocalCache = true
          if start? and end?
            if info.start <= start and info.end >= end
              if info.hasLimits != false
                # need to adjust borders to reasonable limits
                tmp = @_adjustLocalCacheRange(start, end, info.start, info.end)
                syncStart = tmp[0]
                syncEnd = tmp[1]
                @repo.cutCachedCollection(this, syncStart, syncEnd)
              else
                # if the whole collection was cached than we should sync the whole collection
                syncStart = syncEnd = null
            else
              # not using cache if stored borders doesn't comply to the requested
              loadLocalCache = false
          # if no borders are given (whole collection is requested) than we can use cache only if the whole collection
          # was cached (hasLimits == false)
          else if info.hasLimits != false
            loadLocalCache = false

          rangeAdjustPromise.resolve(syncStart, syncEnd)

          if loadLocalCache
            Defer.nextTick => # giving backend sync ability to start HTTP-request
              @repo.getCachedCollectionModels(@name, @_fields).done (models) =>
                @_firstGetModelsFromCachePromise.resolve(models, syncStart, syncEnd)
              .fail (error) =>
                @_firstGetModelsFromCachePromise.reject(error)
          else
            @_firstGetModelsFromCachePromise.reject("Local cache is not applicable for this sync call!")

        .fail (error) => # getCachedCollectionInfo
          rangeAdjustPromise.resolve(start, end)
          @_firstGetModelsFromCachePromise.reject(error)

        @_firstGetModelsFromCachePromise

      else
        resultPromise = Future.single('Collection::_getModelsFromLocalCache')
        @_firstRangeAdjustPromise.done (syncStart, syncEnd) =>
          # in case of repeated async cache request we can use result of the first cache request only if it's range
          #  complies with the second requested range
          if syncStart <= start and syncEnd >= end
            rangeAdjustPromise.resolve(syncStart, syncEnd)
            resultPromise.when @_firstGetModelsFromCachePromise
          else
            rangeAdjustPromise.resolve(start, end)
            resultPromise.reject("Local cache doesn't contain requested range of models!")
        resultPromise


    # serialization related

    toJSON: ->
      models: _.compact(@_models)
      id: @_id
      filterType: @_filterType
      filterId: @_filterId
      filterParams: @_filterParams
      orderBy: @_orderBy
      fields: @_fields
      start: @_loadedStart
      end: @_loadedEnd
      hasLimits: @_hasLimits
      totalCount: @_totalCount
      filter: @_filter
      requestParams: @_requestParams
      pageSize: @_pageSize
      canonicalPath: @constructor.path ? null
      initialized: @_initialized
      _accessPoint: @_accessPoint


    @fromJSON: (repo, name, obj) ->
      CollectionClass = obj.collectionClass ? this
      collection = new CollectionClass(repo, name, {})
      models = []
      start = obj.start
      for m, i in obj.models
        m = repo.buildModel(m)
        m.setCollection(collection)
        models[start + i] = m
      collection._models = models
      collection._id = obj.id
      collection._filterType = obj.filterType
      collection._filterParams = obj.filterParams
      collection._filterId = obj.filterId
      collection._orderBy = obj.orderBy
      collection._fields = obj.fields
      collection._setLoadedRange(start, obj.end)
      collection._hasLimits = obj.hasLimits
      collection._totalCount = obj.totalCount
      collection._filter = obj.filter
      collection._requestParams = obj._requestParams
      collection._pageSize = obj.pageSize
      collection._accessPoint = obj._accessPoint

      collection._reindexModels()
      collection._initialized = obj.initialized || (collection._models.length > 0)
      
      collection


    serializeLink: ->
      ###
      Returns serialized link (address) of this collection
      @return String
      ###
      ":collection:#{ @repo.constructor.__name }:#{ @name }"


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


    _setLoadedRange: (start, end) ->
      @_queryQueue.loadingStart = @_loadedStart = start
      @_queryQueue.loadingEnd = @_loadedEnd = end
      #@_loadedStart = start
      #@_loadedEnd = end


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "(#{ (new Date).getTime() }) #{ @repo.constructor.__name }::#{ @constructor.__name }#{ methodStr }"

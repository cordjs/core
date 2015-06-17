define [
  'cord!isBrowser'
  'cord!Module'
  'cord!errors'
  'cord!utils/Defer'
  'cord!utils/Future'
  'monologue' + (if CORD_IS_BROWSER then '' else '.js')
  'underscore'
], (isBrowser, Module, errors, Defer, Future, Monologue, _) ->

  class ModelNotExists extends errors.CordError
    name: 'ModelNotExists'


  class Collection extends Module
    @include Monologue.prototype

    @__name: 'Collection' # obfuscation support

    _filterType: ':none' # :none | :local | :backend
    _filterId: null
    _filterParams: null # params for filter
    _filterFunction: null
    _reportConfig: null

    _defaultRefreshPages: 3 #default amount of pages to refresh

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

    # Tags for collection refreshing and other activities. Used for background refreshing of collections
    # Tags events are propagated trough appropriate ModelRepo
    # Tag is a user-defined string, collection reaction on tags defined by parameter 'tagsActions'
    # all tag actions are executed within collection context
    # There are predefined tags actions:
    #   'refresh' - immediate refresh loaded parts of the collection
    #   'liveUpdate' - immediate refresh if collection is alive (has any 'change' subscriptons)
    #   'clearCache' - clears cache and timeouts
    # Example:
    # tags:
    # 'project.10000': 'liveUpdate'
    # 'any': 'liveUpdate'
    _tags: null

    # default tag action and proirity for user-defined tags
    @_defaultTagAction: 'tagLiveUpdate'
    @_defaultTagPriority: 100

    # handles tags broadcast
    # params is an object with array of tags and mods (modificators) which wisll be passed as param into tagAction
    # params =
    #   'project.1000002':
    #     ifContain: 1000003
    _handleTagBroadcast: (params) ->
      # Search for mathing tags anf actions
      return if not _.isArray(@_sortedTags)

      for tagObject in @_sortedTags
        tag = tagObject.tag
        tagValue = tagObject.value

        if params[tag] != undefined
          if _.isFunction(tagValue.action)
            if tagValue.action.call(this, params[tag])
              break
          else
            if @[tagValue.action].call(this, params[tag])
              break


    tagsRefresh: (mods) ->
      startPage = @_loadedStart / @_pageSize + 1
      @partialRefresh(startPage, @_defaultRefreshPages, 0, true)
      true


    tagLiveUpdate: (mods) ->
      @_lastQueryTime = 0
      if @hasActiveSubscriptions()
        startPage = if @_pageSize > 0 then @_loadedStart / @_pageSize + 1 else 1
        @partialRefresh(startPage, @_defaultRefreshPages)
        true
      else
        false


    tagClearCache: (mods) ->
      # Clear last query time, which means the collection could be updated
      @_lastQueryTime = 0
      if not @hasActiveSubscriptions()
        @euthanize()
        true
      else
        false


    tagRefreshIfExists: (model) ->
      # Uptade the collection if it already contains the model and has any active 'change' subscriptions
      id = parseInt(if _.isObject(model) then model.id else model)

      if id and not isNaN(id) and @_byId[id] and @hasActiveSubscriptions()
        @refresh(id)
        true
      else
        false


    hasField: (fieldName) ->
      ###
      Detect if collection requests the particular field of part of it
      ###
      for fieldName in @_fields
        return true if fieldName.indexOf(fieldName) == 0
      false


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
      reportConfig = options.reportConfig ? ''
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

      collectionVersion = global.config.static.release

      emitOnAny = if options._emitChangeOnAny then 'emitOnAny' else 'notEmitOnAny'

      tagz = if options.tags then _.keys(options.tags).sort().join('_') else ''

      [
        collectionVersion
        clazz
        accessPoint
        fields.sort().join(',')
        calc.sort().join(',')
        filterId
        filterParams
        filter
        reportConfig
        orderBy
        id
        requestOptions
        pageSize
        tagz
        emitOnAny
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
      @_emitChangeOnAny = options.emitChangeOnAny ? false

      if options.model
        @_fillModelList [options.model]
        @_orderBy = options.orderBy ? null
        @_filterId = null
        @_filterParams = null
        @_id = parseInt(options.model.id)
        @_filter = {}
      else
        @_orderBy = options.orderBy ? null
        @_filterId = options.filterId ? null
        @_filterParams = options.filterParams ? null
        @_reportConfig = options.reportConfig ? null
        @_id = options.id ? 0
        @_filter = options.filter ? {}
        @_pageSize = options.pageSize ? 0

        @_fillModelList(_.values(options.models), options.start, options.end) if options.models

      #special case - fixed collections, when model are already provided and we have no need to do anything with them
      if options.fixed && options.models
        @_fixed = true

      @_requestParams = options.requestParams ? {}
      @_tags = {}

      @_queryQueue =
        loadingStart: @_loadedStart
        loadingEnd: @_loadedEnd
        list: []

      @_accessPoint = options.accessPoint ? null

      # subscribe for model changes to smart-proxy them to the collections model instances
      @_changeSubscription = @repo.on('change', @_handleModelChange).withContext(this)
      @_tagsSubscription = @repo.on('tags', @_handleTagBroadcast).withContext(this)


    injectTags: (tags) ->
      ###
      inject tags into the collections
      ###

      # Parser and initialize tags
      # tags could be set in 3 forms:
      # - a string of tags divided by coma: 'project.100002, project.1000003'
      # - an array of tags: ['project.1000002', 'project.100003']
      # - an object like:
      #   'project.1000003':
      #     action: (mods) -> ...
      #     proiroty: 100
      @_tags = {}
      if tags
        if _.isObject(tags)
          for key, value of tags
            @_tags[key] =
              action: if value.action then value.action else Collection._defaultTagAction
              priority: if not isNaN(Number(value.priority)) then Number(value.priority) else Collection._defaultTagPriority
        else if _.isArray(tags) or _.isString(tags)
          rawTags =
            if _.isString(tags)
              _.filter tags.split(','), item -> item.trim()
            else
              tags

          for value in rawTags
            @_tags[value] =
              action: Collection._defaultTagAction
              priority: Collection._defaultTagPriority
        else
          throw new Error('Unknown \'tags\' option: ' + options.tag)

      if not @_tags['id.any']
        @_tags['id.any'] =
          action: 'tagRefreshIfExists'
          priority: Number.POSITIVE_INFINITY # if no other tags occured

      arrayOfTags = []
      for key, value of @_tags
        arrayOfTags.push
          tag: key
          value: value

      @_sortedTags = _.sortBy arrayOfTags, (tagObject) -> tagObject.value.priority


    euthanize: ->
      ###
      Remove collection from Repo and cache
      ###
      @_changeSubscription.unsubscribe() if @_changeSubscription
      @_tagsSubscription.unsubscribe() if @_tagsSubscription
      @repo.euthanizeCollection(this)


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


    clearLastQueryTime: ->
      @_lastQueryTime = 0


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
                                          :cache-only - return cached collection if initialized (without syncing),
                                                        or reject otherwise
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
      cacheMode = (returnMode == ':cache' or returnMode == ':cache-only')

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
      activateSyncPromise.resolve(true) if not cacheMode
      cacheCompletedPromise = Future.single('Collection::sync cacheCompletedPromise')

      if not @_initialized
        # try to load local storage cache only when syncing first time
        @_getModelsFromLocalCache(start, end, rangeAdjustPromise).spread (models, syncStart, syncEnd) =>
          Defer.nextTick => # give remote sync a chance
            if not firstResultPromise.completed()
              @_fillModelList(models, syncStart, syncEnd) if not @_initialized # the check is need in case of parallel cache trial
              firstResultPromise.resolve(this)
          activateSyncPromise.resolve(false) if cacheMode # remote sync is not necessary in :cache mode
          true
        .catch ->
          if returnMode == ':cache-only'
            activateSyncPromise.resolve(false)
          else if cacheMode
            activateSyncPromise.resolve(true) # cache failed, need to remote sync even in :cache mode
          false
        .link(cacheCompletedPromise)
      else # if @_initialized
        rangeAdjustPromise.resolve([start, end])
        if cacheMode
          # in :cache mode we need to check if requested range is already loaded into the collection's payload
          if start? and end?
            if start >= @_loadedStart and end <= @_loadedEnd
              activateSyncPromise.resolve(false)
              firstResultPromise.resolve(this)
              cacheCompletedPromise.resolve(true)
            else
              activateSyncPromise.resolve(returnMode != ':cache-only')
              cacheCompletedPromise.resolve(false)
              firstResultPromise.resolve(this) if returnMode == ':cache-only'
          else
            if @_hasLimits == false
              activateSyncPromise.resolve(false)
              firstResultPromise.resolve(this)
              cacheCompletedPromise.resolve(true)
            else
              activateSyncPromise.resolve(true)
              cacheCompletedPromise.resolve(false)
              firstResultPromise.resolve(this) if returnMode == ':cache-only'
        else
          cacheCompletedPromise.resolve(false) # not used, only to avoid future timeout

      # sync with backend
      # special promise for :sync mode completion
      syncPromise = activateSyncPromise.then (activate) =>
        if activate
          # wait for range adjustment from the local cache
          rangeAdjustPromise.spread (syncStart, syncEnd) =>
            @_enqueueQuery(syncStart, syncEnd) # avoid repeated refresh-query
          .then =>
            firstResultPromise.resolve(this) if not firstResultPromise.completed()
            this
        else
          this
      .catch (err) ->
        firstResultPromise.reject(err) if not firstResultPromise.completed()
        throw err

      # handling different behaviours of return modes
      resultPromise = Future.single('Collection::sync resultPromise')
      switch returnMode
        when ':sync' then resultPromise.when(syncPromise)
        when ':async'
          syncPromise.failOk()
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
        when ':cache-only'
          cacheCompletedPromise.then (cacheHit) =>
            if cacheHit
              firstResultPromise
            else
              throw new Error('Cache sync failed in :cache-only mode')
          .link(resultPromise)

      resultPromise.then =>
        callback?(this)
      .failOk()
      resultPromise


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
      # This method returns array of loaded models.
      # Warning! Probably you should not use this function for paged collections, but getPage()
      @_models


    isInitialized: ->
      ###
      Indicates that the collection is already synchronized at least once.
      @return Boolean
      ###
      @_initialized


    checkNewModel: (model, emitModelChangeExcept = true) ->
      ###
      Checks if the new model is related to this collection. If it is reloads collection from the backend.
      @param Model model the new model
      ###
      id = parseInt(if _.isObject(model) then model.id else model)
      if (not @_id or (not isNaN(id) and parseInt(@_id) == id)) and @hasActiveSubscriptions()
        @refresh(id, @_defaultRefreshPages, 0, emitModelChangeExcept)


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


    hasActiveSubscriptions: ->
      ###
      Returns true if refresh allowed, which means
      1. there's no other refreshes in progress
      2. the collection is not fixed
      3. the collection has at least one 'change' subscription
      ###
      if @_fixed #or @_refreshInProgress
        false
      else if not @_hasActiveChangeSubscriptions()
        false
      else
        true


    partialRefresh: (startPage, maxPages, minRefreshInterval = 0) ->
      ###
      Reloads olny maxPages pages of the collection only if the collection hasn't been refreshed for required interval
      Useful for potentilally huge collections
      ###
      # _console.log "#{ @repo.restResource } partialRefresh: (startPage=#{startPage}, maxPages=#{maxPages}, minRefreshInterval=#{minRefreshInterval})"
      return Future.resolved(this) if @_fixed

      startPage = Number(startPage)
      maxPages = Number(maxPages)

      # This is actually for debugging purposes
      if isNaN(startPage) or isNaN(maxPages) or startPage < 1 or maxPages <1
        error =  new Error("collection.partialRefresh called with wront parameters startPage: #{startPage}, maxPages: #{maxPage}")
        return Future.rejected(error)

      if minRefreshInterval >= 0 and @getLastQueryTimeDiff() > minRefreshInterval
        @_refreshInProgress = true
        if not @_pageSize
          @_fullReload()
        else
          @_simplePageRefresh(startPage, maxPages)
      else
        Future.resolved(this)


    refresh: (currentId, maxPages = @_defaultRefreshPages, minRefreshInterval = 0, emitModelChangeExcept = true) ->
      ###
      Reloads currently loaded part of collection from the backend.
      By the way triggers change events for every changed model and for the collection if there are any changes.
      todo: support of single-model collections
      @param int currentId - id of currently used model (selected or showed),
      @param int maxPages  - amount of pages to be refreshed, the rest of the collection will be cleaned
      if currentId and pageSize are defined, refresh will start from page, containing the currentId model, going up and down
      ###

      #_console.log "#{ @repo.restResource } refresh: (currentId=#{currentId}, emitModelChangeExcept=#{emitModelChangeExcept}, maxPages=#{maxPages})"

      return Future.resolved(this) if @_fixed

      return if not (minRefreshInterval >= 0 and @getLastQueryTimeDiff() > minRefreshInterval)

      @_refreshInProgress = true

      # Refresh all models at once if no paging used
      if not @_pageSize
        @_fullReload()
      else
        # Try to catch some architectural errors
        if isNaN(Number(currentId))
          _console.error('collection.refresh called with wrong parameter currentId', currentId, new Error())
          return

        if maxPages < 1
          _console.error('collection.refresh called with wrong parameter maxPages', maxPages, new Error())

        # Collection boundaries
        startPage = Math.floor(@_loadedStart / @_pageSize) + 1
        endPage = Math.ceil(@_loadedEnd / @_pageSize)

        # Check if the model is already in the collection, which means we know where to start
        if @_byId[currentId]
          modelIndex = _.indexOf @_models, @_byId[currentId]
          modelPage = Math.ceil((modelIndex + 1) / @_pageSize)
          @_sophisticatedRefreshPage(modelPage, startPage, endPage, maxPages)

        else
          # If model is not in the collection than we have to check if the model belongs to the collection
          # The best way to do this is to make a paging request
          @getPagingInfo(currentId, true).failAloud().done (paging) =>
            if paging.pages == 0
              # special case, when collection nullifies on server
              @_replaceModelList([], @_loadedStart, @_loadedEnd)
              @_refreshInProgress = false
            else if paging.selectedPage > 0
              # Don't refresh collection if currentId is not belonged to it
              @_sophisticatedRefreshPage(paging.selectedPage, startPage, endPage, maxPages)
            else
              @_refreshInProgress = false


    _fullReload: ->
      ###
      Completely reloads all collection at once
      ###
      # _console.log '_fullReload'
      queryParams = @_buildRefreshQueryParams()
      @repo.query queryParams, (models) =>
        @_replaceModelList(models, queryParams.start, queryParams.end)
        @_refreshInProgress = false



    _simplePageRefresh: (startPage, maxPages, loadedPages = 0) ->
      ###
      Simple refreshes few pages one by one
      ###
      # _console.log "#{ @repo.restResource } _simplePageRefresh: (startPage=#{startPage}, maxPages=#{maxPages}, loadedPages=#{loadedPages}) ->"
      if startPage < 1 or maxPages < 1
        error = new Error('collection._simplePageRefresh got bad parameters.')
        _console.error(error)
        Future.rejected(error)
      else
        start = (startPage - 1) * @_pageSize
        end = startPage * @_pageSize - 1

        # We'll continue refreshing if [start,end] intersects with [@_loadedStart, @_loadedEnd]
        if (start <= @_loadedStart <= end or start <= @_loadedEnd <= end) and loadedPages + 1 <= maxPages
          @_enqueueQuery(start, end, true).failAloud().done =>
            @_simplePageRefresh(startPage + 1, maxPages, loadedPages + 1)
        else
          @_refreshInProgress = false
          Future.resolved()


    _sophisticatedRefreshPage: (page, startPage, endPage, maxPages = @_defaultRefreshPages, direction = 'down', loadedPages = 0) ->
      # _console.log "#{ @repo.restResource } _sophisticatedRefreshPage: (page=#{page}, startPage=#{startPage}, endPage=#{endPage}, maxPages=#{maxPages}, direction=#{direction}, loadedPages=#{loadedPages})"

      start = (page - 1) * @_pageSize
      end = page * @_pageSize - 1

      if page > 0 and loadedPages < maxPages and (start <= @_loadedStart <= end or start <= @_loadedEnd <= end)
        @_enqueueQuery(start, end, true).done =>
          if not @_refreshReachedTop
            @_refreshReachedTop = page == startPage

          if not @_refreshReachedBottom
            @_refreshReachedBottom = page == endPage

          if @_refreshReachedTop
            direction = 'down'
          else if @_refreshReachedBottom
            direction = 'up'
          else
            direction = if direction == 'up' then 'down' else 'up'

          @_topPage = page if not @_topPage
          @_bottomPage = page if not @_bottomPage

          if direction == 'up'
            page = @_topPage = @_topPage - 1
          else
            page = @_bottomPage = @_bottomPage + 1

          @_sophisticatedRefreshPage(page, startPage, endPage, maxPages, direction, loadedPages + 1)
        .fail (message) =>
          @_topPage = 0
          @_bottomPage = 0
          @_refreshReachedTop = false
          @_refreshReachedBottom = false
          @_refreshInProgress = false
          _console.error('collection._sophisticatedRefreshPage _enqueueQuery error: ', message)
      else
        # total flush
        @_topPage = 0
        @_bottomPage = 0
        @_refreshReachedTop = false
        @_refreshReachedBottom = false
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
        result.reportConfig = @_reportConfig if @_reportConfig?
      result


    _hasActiveChangeSubscriptions: ->
      return false if not @_subscriptions
      return true if @_subscriptions.change and @_subscriptions.change.length > 0

      for topic, subscriptions of @_subscriptions
        return true if subscriptions.length > 0 and topic.substr(-6) == 'change'

      false


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
        modelPage = Math.ceil((modelIndex + 1) / @_pageSize)

      changedModels = {}
      changedModels[model.id] = model

      if @_loadedStart > @_loadedEnd
        @_loadedStart = @_loadedEnd = 0
      else
        @_loadedEnd++

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

      oldListCount = 0
      oldList = _.clone(@_models)

      if (start? and end?) and (start < end)
        ###
        #in case of refreshing, we'll just replace the list
        if start == @_loadedStart && end == @_loadedEnd
          @_fillModelList newList
          return true
        ###

        loadingStart = oldListStart = start
        loadingEnd = oldListEnd = end
        @_models = _.clone(@_models)
      else
        loadingStart = oldListStart = 0
        oldListEnd = oldList.length - 1
        loadingEnd = newList.length - 1
        @_models = []

      firstChangedIndex = @_models.length
      lastChangedIndex = 0

      deleted = false
      deletedModels = {}
      changed = false
      changedModels = {}

      newListIds = {}
      for item in newList
        newListIds[item.id] = item

      for i in [oldListStart..oldListEnd] by 1
        model = oldList[i]

        # Бывает так, что в списке моделей есть пропуски... Надо с этим разобраться.
        continue if not model

        oldListCount++

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
      else if loadingEnd == -1 and @_loadedEnd == -1
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
        if @repo.hasFieldCompareFunction(field)
          return true if @repo.fieldCompareFunction(field, model1[field], model2[field])

        else if field != 'id' and not @_modelsEq(model1[field], model2[field])
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


    _recursiveCompareAndChange: (src, dst, level = 0) ->
      ###
      Deeply rewrites values from the source object to the corresponding keys of the destination object.
      Only existing keys of the destination model are changed, no new keys are added.
      If the value is object than recursively calls itself.
      @param Object src source object
      @param Object dst destination object
      @param Int level internal counter of recursion level
      @return Boolean true if the destination object was changed
      ###
      result = false

      for key, val of src
        continue if dst[key] == undefined

        if level == 0 and @repo.hasFieldCompareFunction(key)
          if @repo.fieldCompareFunction(key, val, dst[key])
            dst[key] = _.clone(val)
            result = true

        else if _.isArray(val) and _.isArray(dst[key])
          if val.length == 0
            #If dst was an array longer than 0
            if not _.isArray(dst[key]) or dst[key].length > 0
              dst[key] = []
              result = true
#          else
#            for newVal, newKey in val
#              if dst[key][newKey] == undefined or @_recursiveCompare(newVal, dst[key][newKey])
#                dst[key] = _.clone(val)
#                result = true
#                break

        else if _.isObject(val) and _.isObject(dst[key])
          if @_recursiveCompareAndChange(val, dst[key], level + 1)
            result = true

        # typeof null == typeof {}, but we dont want it
        else if typeof val == typeof dst[key] and val != null and dst[key] != null and not _.isEqual(val, dst[key])
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
          else if @_recursiveCompare(val, dst[key])
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
        # If not excepted model
        if @_selfEmittedChangeModelId != changeInfo.id
          modelHasReallyChanged = @_recursiveCompareAndChange(changeInfo, model)
          isSourceModel = changeInfo._sourceModel == model
          if isSourceModel or modelHasReallyChanged
            @emit("model.#{ changeInfo.id }.change", model)
            if @_emitChangeOnAny
              if not @_globalChangeEmitRequired
                Defer.nextTick =>
                  @_globalChangeEmitRequired = false
                  @emit('change', {})
              @_globalChangeEmitRequired = true


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
          @_models.slice(start, end + 1)
        else
          @_models

      #sometimes collection could be toren apart, check for this case
      (if @_loadedStart <= start and (@_loadedEnd >= end || @_totalCount == @_loadedEnd + 1) and @isConsistent((sliced = slice())) == true
        Future.resolved(sliced)
      else
        @sync(':async', start, end).then -> [slice()] ## todo: Future refactor
      ).rename('Collection::getPage')


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

      # Workaround for fixed collections
      if @_fixed
        result.resolve
          total: @_models.length
          pages: if @_models.length then 1 else 0
          selectedPage: if @_models.length then 1 else 0

        return result

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
            if (m = @_byId[selectedId])? or @_totalCount == 0 # Empty collection is a valid collection as well
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
          params.reportConfig = @_reportConfig if @_reportConfig?

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

      if ( not end? || (end - start > 5000) ) && not @_id && not @repo._debugCanDoUnlimit
        _console.warn 'ACHTUNG!!! Me bumped into unlimited query: end =', end, 'start =', start, @repo.restResource

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
        # attaching to the last query's in the queue promise
        if (lastQuery = _.last(queryList))?
          prevQueryPromise = lastQuery.promise
        else
          prevQueryPromise = Future.resolved()

        # starting to process query only after completion of the previous in the queue
        queryPromise = prevQueryPromise.then =>
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
            queryParams.reportConfig = @_reportConfig if @_reportConfig?
            queryParams.start = start if start?
            queryParams.end = end  if end?

          queryParams.requestParams = @_requestParams if @_requestParams
          queryParams.accessPoint = @_accessPoint if @_accessPoint

          @updateLastQueryTime()
          @repo.query(queryParams)
        .then (models) =>
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

          this
#        .catch (error) =>
#          _console.error "#{@constructor.__name}::_enqueueQuery() query failed:", error
#          false

        waitForQuery =
          start: start
          end: end
          type: queryType
          promise: queryPromise

        queryList.push(waitForQuery)

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

          rangeAdjustPromise.resolve([syncStart, syncEnd])

          if loadLocalCache
            Defer.nextTick => # giving backend sync ability to start HTTP-request
              @repo.getCachedCollectionModels(@name, @_fields).then (models) ->
                [[models, syncStart, syncEnd]] ## todo: Future refactor
              .link(@_firstGetModelsFromCachePromise)
          else
            @_firstGetModelsFromCachePromise.reject(new Error('Local cache is not applicable for this sync call!'))

        .fail (error) => # getCachedCollectionInfo
          rangeAdjustPromise.resolve([start, end])
          @_firstGetModelsFromCachePromise.reject(error)

        @_firstGetModelsFromCachePromise

      else
        resultPromise = Future.single('Collection::_getModelsFromLocalCache')
        @_firstRangeAdjustPromise.spread (syncStart, syncEnd) =>
          # in case of repeated async cache request we can use result of the first cache request only if it's range
          #  complies with the second requested range
          if syncStart <= start and syncEnd >= end
            rangeAdjustPromise.resolve([syncStart, syncEnd])
            resultPromise.when @_firstGetModelsFromCachePromise
          else
            rangeAdjustPromise.resolve([start, end])
            resultPromise.reject(new Error("Local cache doesn't contain requested range of models!"))
          return
        resultPromise


    # serialization related

    toJSON: ->
      models: _.compact(@_models)
      id: @_id
      filterType: @_filterType
      filterId: @_filterId
      filterParams: @_filterParams
      reportConfig: @_reportConfig
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
      emitChangeOnAny: @_emitChangeOnAny
      _accessPoint: @_accessPoint
      _fixed: !!@_fixed


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
      collection._id = parseInt(obj.id)
      collection._filterType = obj.filterType
      collection._filterParams = obj.filterParams
      collection._filterId = obj.filterId
      collection._reportConfig = obj.reportConfig
      collection._orderBy = obj.orderBy
      collection._fields = obj.fields
      collection._setLoadedRange(start, obj.end)
      collection._hasLimits = obj.hasLimits
      collection._totalCount = obj.totalCount
      collection._filter = obj.filter
      collection._requestParams = obj.requestParams
      collection._pageSize = obj.pageSize
      collection._emitChangeOnAny = obj.emitChangeOnAny
      collection._accessPoint = obj._accessPoint
      collection._reindexModels()
      collection.injectTags()
      collection._initialized = obj.initialized || (collection._models.length > 0)
      collection._fixed = !!obj._fixed

      collection


    serializeLink: ->
      ###
      Returns serialized link (address) of this collection
      @return String
      ###
      @repo.markAsUsed()
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
      if serialized instanceof Collection
        callback(serialized)
      else
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

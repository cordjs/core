define [
  'cord!utils/Future'
  'cord!utils/sha1'
  'cord!cookie/LocalCookie'
  'cord!errors'
], (Future, sha1, LocalCookie, errors) ->

  class LocalStorage

    persistentKey: 'storage.persistent'

    constructor: (@storage, @logger) ->
      # Max amount of time to waint until reject @getItem and clear localStorage
      # Made this value bigger according to http://calendar.perfplanet.com/2012/is-localstorage-performance-a-problem/
      @_getTimeout = 1000


    saveCollectionInfo: (repoName, collectionName, ttl, info) ->
      ###
      Saves only collections meta-information
      ###
      key = "cl:#{ repoName }:#{ sha1(collectionName) }"
      if ttl?
        @_registerTtl(key + ':info', ttl)
        @_registerTtl(key, ttl)
      @_set(key + ':info', info)


    saveCollection: (repoName, collectionName, modelIds) ->
      ###
      Saves list of model ids for the collection.
      ###
      @_set("cl:#{ repoName }:#{ sha1(collectionName) }", modelIds)


    invalidateCollection: (repoName, collectionName) ->
      ###
      Removes collection from cache
      ###
      key = "cl:#{ repoName }:#{ sha1(collectionName) }"
      @_removeItem key
      @_removeItem(key + ':info')


    invalidateAllCollectionsWithField: (repoName, fieldName) ->
      ###
      Clear cache for collections of particular repo, which contains the fieldName
      ###
      @_invalidateAllCollectionsWithField repoName, fieldName


    getCollectionInfo: (repoName, collectionName) ->
      ###
      Returns meta-information of the collection, previously saved in the local storage.
      ###
      @_get("cl:#{ repoName }:#{ sha1(collectionName) }:info")


    getCollection: (repoName, collectionName) ->
      ###
      Returns list of model ids of the collection, previously saved in the local storage.
      ###
      @_get("cl:#{ repoName }:#{ sha1(collectionName) }")


    getItem: (key) ->
      ###
      getItem wrapper
      ###
      @_get(key) if key != @persistentKey


    setItem: (key, value) ->
      ###
      setItem wrapper
      ###
      @_set(key, value) if key != @persistentKey


    removeItem: (key) ->
      ###
      removeItem wrapper
      ###
      @_removeItem(key) if key != @persistentKey


    clear: ->
      ###
      Future-powered clear local storage
      We should use new future, because storage.clear return native future and we can't catch it
      ###
      return @clearPromise if @clearPromise?
      result = Future.single('localStorage::clear')
      @clearPromise = result

      @_get(@persistentKey).then (persistentValues) =>
        @_get(LocalCookie.storageKey).then (cookies) =>
          @storage.clear =>
            futures = []
            futures.push(@_set(@persistentKey, persistentValues)) if persistentValues
            futures.push(@_set(LocalCookie.storageKey, cookies)) if cookies
            Future.all(futures).then ->
              result.resolve()
        .catch =>
          @storage.clear =>
            @_set(@persistentKey, persistentValues) if persistentValues
            result.resolve()
      .catch =>
        # this is ok, just clear and resolve
        @storage.clear()
        result.resolve()

      result


    _removeItem: (key) ->
      result = Future.single('localStorage::_removeItem')
      try
        @storage.removeItem key, ->
          result.resolve()
      catch e
        result.reject(e)
      result


    _set: (key, value) ->
      ###
      Key-value set proxy for the local storage with serialization and garbage collection fired when not enough space.
      Garbage collection is base on the TTL params, passed when saving values.
      ###
      result = Future.single("localStorage::_set #{key}")
      try
        @storage.setItem key, value, ->
          result.resolve()
      catch e
        if e.code == DOMException.QUOTA_EXCEEDED_ERR or e.name.toLowerCase().indexOf('quota') != -1
          @_gc(value.length)
          try
            @storage.setItem key, value, ->
              result.resolve()
          catch e
            @logger.error "localStorage::_set(#{ key }) failed!", value, e
            result.reject(e)
        else
          result.reject(e)
      result


    _get: (key) ->
      ###
      Future-powered proxy key-value get method.
      ###
      result = Future.single("localStorage::_get #{key}")

      # Protection against localStorage going crazy (because of overflow?), when @storage.getItem never calls callback in Chrome
      setTimeout =>
        if result.state() == 'pending'
          @clear() if not @clearPromise?
          result.reject(new errors.ItemNotFound("LocalStorage timeouted with key #{key}!"))
      , @_getTimeout

      @storage.getItem key, (value) ->
        if result.state() == 'pending'
          if value?
            result.resolve(value)
          else
            result.reject(new errors.ItemNotFound("Key '#{key}' doesn't exists in the local storage!"))

      result


    _registerTtl: (key, ttl) ->
      ###
      Saves TTL for the given key to be able to make right decisions during GC
      ###
      @storage.getItem 'models:ttl-info', (ttlInfo) =>
        ttlInfo = {} if ttlInfo == null
        ttlInfo[key] = (new Date).getTime() + ttl

        @_set('models:ttl-info', ttlInfo)


    _gc: (needLength) ->
      ###
      Garbage collector.
      If needLength argument is given, than it tries to free just enought space, if not - all expired items are removed.
      @param (optional) needLength amount of memory needed
      ###
      @storage.getItem 'models:ttl-info', (ttlInfo) =>
        if needLength
          needLength = parseInt(needLength) * 2
        else
          needLength = 0
        orderedTtlInfo = []
        for k, v of ttlInfo
          orderedTtlInfo.push [k, v]
        orderedTtlInfo = _.sortBy orderedTtlInfo, (x) -> x[1]

        if needLength
          while needLength > 0 and orderedTtlInfo.length
            item = orderedTtlInfo.shift()
            @storage.getItem item[0], (val) ->
              if val?
                needLength -= val.length
                @storage.removeItem(item[0])
              delete ttlInfo[item[0]]
        else
          currentTime = (new Date).getTime()
          for item in orderedTtlInfo
            if item[1] < currentTime
              @storage.removeItem(item[0])
              delete ttlInfo[item[0]]
            else
              break

        @_set('models:ttl-info', ttlInfo)


    _invalidateAllCollectionsWithField: (repoName, fieldName) ->
      @storage.length().then (length) =>
        promises = []
        for index in [0..length-1]
          @storage.key(index).then (key) =>
            if key and key.slice(-5) == ':info' && key.indexOf(repoName) >= 0
              if not fieldName
                promises.push(@_clearItem key)
              else
                @storage.getItem(key).then (value) =>
                  if not value.fields || (fieldName in value.fields)
                    promises.push(@_clearItem key)

        Promise.all(promises)
      .toFuture()


    _clearItem: (key) ->
      ###
      Очищает ключ в кэше, одновременно очищая его вариант без сууфикса ':info'
      ###
      @logger.assertLazy "Local storage key (#{key}) should end up with \":info\"", ->
        key.slice(-5) == ':info'

      Promise.all [
        @storage.removeItem(key)
        @storage.removeItem(key.slice(0, key.length - 5))
      ]


    _invalidateAllCollections: (repoName) ->
      @storage.length().then (length) =>
        promises = []
        for index in [1..length-1]
          @storage.key(index).then (key) =>
            if key and key.slice(-5) == ':info' and key.indexOf(repoName) >= 0
              promises.push(@_clearItem key)
        Promise.all(promises)
      .toFuture()

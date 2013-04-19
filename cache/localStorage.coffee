define [
  'cord!utils/Future'
], (Future) ->

  class LocalStorage

    storage: window.localStorage


    saveCollectionInfo: (repoName, collectionName, ttl, info) ->
      ###
      Saves only collections meta-information
      ###
      key = "cl:#{ repoName }:#{ collectionName }"
      if ttl?
        @_registerTtl(key + ':info', ttl)
        @_registerTtl(key, ttl)
      @_set(key + ':info', info)


    saveCollection: (repoName, collectionName, modelIds) ->
      ###
      Saves list of model ids for the collection.
      ###
      @_set("cl:#{ repoName }:#{ collectionName }", modelIds)


    getCollectionInfo: (repoName, collectionName) ->
      ###
      Returns meta-information of the collection, previously saved in the local storage.
      ###
      @_get("cl:#{ repoName }:#{ collectionName }:info")


    getCollection: (repoName, collectionName) ->
      ###
      Returns list of model ids of the collection, previously saved in the local storage.
      ###
      @_get("cl:#{ repoName }:#{ collectionName }")


    getModel: (repoName, id) ->
      ###
      Returns fields of the model instance with the given id, previously saved in the local storage.
      ###
      @_get("m:#{ repoName }:#{ id }")


    _set: (key, value) ->
      ###
      Key-value set proxy for the local storage with serialization and garbage collection fired when not enough space.
      Garbage collection is base on the TTL params, passed when saving values.
      ###
      result = Future.single()
      strValue = JSON.stringify(value)
      try
        @storage.setItem(key, strValue)
        result.resolve()
      catch e
        if e.name == 'QUOTA_EXCEEDED_ERR'
          @_gc(strValue.length)
          try
            @storage.setItem(key, strValue)
            result.resolve()
          catch e
            console.error "localStorage::_set(#{ key }) failed!", value, e
            result.reject(e)
        else
          result.reject(e)
      result


    _get: (key) ->
      ###
      Future-powered proxy key-value get method.
      ###
      value = @storage.getItem(key)
      if value?
        Future.resolved(JSON.parse(value))
      else
        Future.rejected("Key '#{ key }' doesn't exists in the local storage!")


    _registerTtl: (key, ttl) ->
      ###
      Saves TTL for the given key to be able to make right decisions during GC
      ###
      ttlInfo = @storage.getItem('models:ttl-info')
      ttlInfo ?= {}

      ttlInfo[key] = (new Date).getTime() + ttl

      @_set('models:ttl-info', ttlInfo)


    _gc: (needLength) ->
      ###
      Garbage collector.
      If needLength argument is given, than it tries to free just enought space, if not - all expired items are removed.
      @param (optional) needLength amount of memory needed
      ###
      console.warn "localStorage::GC !"
      ttlInfo = @storage.getItem('models:ttl-info')
      if needLength
        needLength = parseInt(needLength) * 2
      else
        needLength = 0
      orderedTtlInfo = []
      for k, v of ttlInfo
        orderedTtlInfo.push [k, v]
      orderedTtlInfo = _.sortBy orderedTtlInfo, (x) -> x[1]

      if needLength
        while needLength > 0
          item = orderedTtlInfo.shift()
          needLength -= @storage.getItem(item[0]).legnth
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



  new LocalStorage

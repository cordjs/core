define [
  'cord!Model'
  'cord!Collection'
  'cord!utils/Future'
], (Model, Collection, Future) ->

  class ModelProxy

    _modelLinks: []
    _collectionLinks: []
    _arrayLinks: []

    @inject: ['container']


    addModelLink: (object, field) ->
      console.log 'addModelLink: (object, field) ->', object, field
      @_modelLinks.push object: object, field: field


    addCollectionLink: (object, field) ->
      console.log 'addCollectionLink: (object, field) ->', object, field
      @_collectionLinks.push object: object, field: field


    addArrayLink: (object, field) ->
      console.log 'addArrayLink: (object, field) ->', object, field
      @_arrayLinks.push object: object, field: field


    restoreLinks: ->
      promise = new Future

      for link in @_modelLinks
        promise.fork()
        Model.unserializeLink item, @container, (model) ->
          link.object[link.field] = model
          promise.resolve()

      for link in @_collectionLinks
        promise.fork()
        Collection.unserializeLink item, @container, (collection) ->
          link.object[link.field] = collection
          promise.resolve()

      for link in @_arrayLinks
        storedLinks = link.object[link.field]
        link.object[link.field] = []
        for item in storedLinks
          promise.fork()
          Model.unserializeLink item, @container, (model) ->
            link.object[link.field].push(model)
            promise.resolve()

      promise

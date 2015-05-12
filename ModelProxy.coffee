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
      @_modelLinks.push object: object, field: field


    addCollectionLink: (object, field) ->
      @_collectionLinks.push object: object, field: field


    addArrayLink: (object, field) ->
      @_arrayLinks.push object: object, field: field


    restoreLinks: ->
      promises = []

      for link in @_modelLinks
        promises.push(
          Model.unserializeLink(link.object[link.field], @container).then (model) ->
            link.object[link.field] = model
            return
        )

      for link in @_collectionLinks
        promises.push(
          Collection.unserializeLink(link.object[link.field], @container).then (collection) ->
            link.object[link.field] = collection
            return
        )

      for link in @_arrayLinks
        storedLinks = link.object[link.field]
        link.object[link.field] = []
        for item in storedLinks
          promises.push(
            Model.unserializeLink(item, @container).then (model) ->
              link.object[link.field].push(model)
              return
          )

      Future.all(promises)

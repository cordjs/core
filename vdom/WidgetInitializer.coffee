define [
  'cord!utils/Future'
], (Promise) ->

  class WidgetInitializer
    ###
    Incapsulates widget transferring and restoring from server to browser logic
    ###

    @inject: [
      'widgetFactory'
      'widgetRepo' # old widgets repository
    ]

    # {Object.<string, Promise.<Widget>>} map of widget init promises
    # used to wait for parent widgets to be initialized before child widget
    _widgetInitPromises: null


    constructor: ->
      @_widgetInitPromises = {}


    init: ->
      ###
      Compatibility proxy-method to support old widgets initialization
      ###
      @widgetRepo.init.apply(@widgetRepo, arguments)


    endInit: ->
      ###
      Compatibility proxy-method to support old widgets initialization
      ###
      @widgetRepo.endInit()


    restoreModelLinks: ->
      ###
      Compatibility proxy-method to support old widgets initialization
      ###
      @widgetRepo.restoreModelLinks.apply(@widgetRepo, arguments)


    vdomInit: (id, widgetPath, props, state, parentId) ->
      ###
      Restores vDom widget transferred from server to browser
      @param {string} id
      @param {string} widgetPath
      @param {Object.<string, *>} props
      @param {Object.<string, *>} state
      @param {string=} parentId
      ###
      parentPromise = (parentId and @_widgetInitPromises[parentId]) or Promise.resolved()
      @_widgetInitPromises[id] = parentPromise.then =>
        @widgetFactory.restore(widgetPath, id, props, state, parentId)
      return

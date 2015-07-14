define [
  'cord!Widget'
  'cord!utils/Future'
], (OldWidget, Promise) ->

  class WidgetInitializer
    ###
    Incapsulates widget transferring and restoring from server to browser logic
    ###

    @inject: [
      'vdomWidgetRepo'
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
      result = @widgetRepo.init.apply(@widgetRepo, arguments)
      # registering old shim-widget in vdom widgets repository
      result.then (widget) =>
        if @_widgetInitPromises
          if @_widgetInitPromises[widget.ctx.id]
            @_widgetInitPromises[widget.ctx.id].resolve(widget)
          else
            @_widgetInitPromises[widget.ctx.id] = Promise.resolved(widget)
      result


    endInit: ->
      ###
      Performs final initialization of the transferred from the server-side objects on the browser-side.
      This method should be called when all widgets initialization method are called.
      Also performs cleaning on widget init promises when they are not needed anymore.
      @return {Promise.<undefined>}
      ###
      Promise.all(_.values(@_widgetInitPromises)).then =>
        @_widgetInitPromises = null
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
      parentPromise =
        if parentId
          @_widgetInitPromises[parentId] = Promise.single() if not @_widgetInitPromises[parentId]
          @_widgetInitPromises[parentId]
        else
          Promise.resolved()
      @_widgetInitPromises[id] = parentPromise.then (parentWidget) =>
        restoreParentId = if parentWidget.id then parentId else undefined
        @widgetFactory.restore(widgetPath, id, props, state, restoreParentId).then (widget) =>
          if parentWidget instanceof OldWidget
            # this is case when vdom-widget is a child of an old-widget
            # special logic for registering as a child
            widget.ctx = id: widget.id
            parentWidget.registerChild(widget, @widgetRepo.widgets[parentId].namedChilds[widget.id] ? null)
          widget
      .failAloud()
      return

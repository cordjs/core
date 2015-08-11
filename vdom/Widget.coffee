define [
  'cord!css/browserManager'
  'cord!utils/Future'
  'cord!vdom/vhyperscript/h'
  'cord!vdom/vstringify/stringify'
  'cord!vdom/vtree/diff'
  'cord!vdom/vtree/vtree'
  'cord!vdom/vtree/utils'
  'underscore'
], (cssManager, Promise, h, stringify, diff, vtree, vtreeUtils, _) ->

  class Widget

    @inject: [
      'domPatcher'
      'vdomWidgetRepo'
      'widgetFactory'
      'widgetHierarchy'
    ]


    constructor: (params = {}) ->
      ###
      Constructor accepts key-value optional params:
      * {string} id - widget's id (only during restoring from server)
      * {Object} props - widget props came from parent widget or router
      * {Object} state - widget's internal state (only during restoring from server)
      ###
      @constructor._init()  if @constructor._initialized != @constructor # consider inheritance

      @id = params.id or ((if CORD_IS_BROWSER then 'b' else 'n') + _.uniqueId())
      @props = params.props or {}
      @state = params.state or prepareInitialState(this)


    destructor: ->
      ###
      Cleans up widget's state and links when the widget is removed.
      ###
      child.drop()  for child in @widgetHierarchy.getChildren(this)
      @_destroyAlienWidgets()
      return


    drop: ->
      ###
      Destroys and removes the widget instance from all repositories.
      Doesn't touch the DOM representation of the widget
      ###
      @destructor()
      @vdomWidgetRepo.unregisterWidget(this)
      @widgetHierarchy.unregisterWidget(this)
      return


    updateProps: (newProps) ->
      @_restoreCurrentVtree().then =>
        changed = false
        for key, value of newProps
          # TODO replace with more sophisticated logic from Context
          if @props[key] != value
            changed = true
            @props[key] = value
        @render()  if changed
        return


    setState: (stateVars) ->
      ###
      Updates widget's state according to the given key-value pairs.
      Doesn't touch state vars that are not present in the given object
      @param {Object.<string, *>} stateVars
      @return {Promise.<undefined>} the promise is fulfilled when this change is applied to the DOM
      ###
      @_restoreCurrentVtree().then =>
        changed = false
        for key, value of stateVars
          # TODO replace with more sophisticated logic from Context
          if @state[key] != value
            changed = true
            @state[key] = value
        @render() if changed


    render: ->
      ###
      Updates the view via rendering vdom-template against current props and state,
       diffing result with the previous vtree and patching the DOM.
      @return {Promise.<undefined>} resolved when DOM is patched
      ###
      @_renderVtree().then (newVtree) ->
        patches = diff(@_vtree, newVtree)
        rootElement = document.getElementById(@id)
        @domPatcher.patch(rootElement, patches, this).then =>
          @_vtree = newVtree
          return
      .failAloud()


    renderDeepTree: ->
      ###
      Renders the widget with dereferencing child widgets (rendering them to the simple VNodes) deeply.
      @return {Promise.<VNode>}
      ###
      @_renderVtree().then (vnode) ->
        @_vtree = vnode
        @_recDereferenceTree(vnode)


    _recDereferenceTree: (vnode) ->
      ###
      Recursively scans the given VNode and replaces VWidget occurences with the rendered widget VNode
      @param {VNode} vnode
      @return {Promise.<VNode>}
      ###
      if vtree.isWidget(vnode)
        @_renderDeepVWidget(vnode)
      else if vtree.isVNode(vnode)
        vnode = vtreeUtils.clone(vnode) # cloning is necessary to avoid dereferencing currently stored @_vtree
        promises = (@_recDereferenceTree(child) for child in vnode.children)
        Promise.all(promises).then (dereferencedChildren) ->
          vnode.children = dereferencedChildren
          vnode
      else
        Promise.resolved(vnode)


    _renderDeepVWidget: (vwidget) ->
      ###
      Renders (dereference) VWidget node and recursively dereference it's VTree.
      @param {VWidget} vwidget
      @return {Promise.<VNode>}
      ###
      @widgetFactory.createByVWidget(vwidget, this).then (widget) ->
        widget.renderDeepTree()


    _renderVtree: ->
      ###
      Renders the widget's template to the virtual DOM tree, using current state and props
      @return {Promise.<VNode>} the promise is bound to `this` widget context
      ###
      calc = {}
      @onRender?(calc)

      renderResult = @constructor.__render(@props, @state, calc)
      renderResult = Promise.resolved(renderResult)  if not (renderResult instanceof Promise)
      renderResult.bind(this).then (vnode) ->
        vnode.properties.id = @id
        vnode


    _restoreCurrentVtree: ->
      ###
      @return {Promise.<VTree>}
      @todo protect from calling twice concurrently
      ###
      if not @_vtree
        @_renderVtree().then (vtree) ->
          @_vtree = vtree
      else
        Promise.resolved(@_vtree)


    _destroyAlienWidgets: ->
      ###
      Destroys all alien widgets in the current widget's virtual-tree
      ###
      if @_vtree
        rootElement = document.getElementById(@id)
        vtreeUtils.destroyAlienWidgets(@_vtree, rootElement)
      return


    getInitCode: (parentId) ->
      ###
      @todo: move to the widgetInitializer service
      ###
      parentStr = if parentId? then ",'#{ parentId }'" else ''

      # todo: maybe add refs (aka childByName)

      # todo: add model bindings serialization

      # filter bad unicode characters before sending data to browser
      propsStr = unescape(encodeURIComponent(JSON.stringify(@props))).replace(/<\/script>/g, '<\\/script>')
      stateStr = unescape(encodeURIComponent(JSON.stringify(@state))).replace(/<\/script>/g, '<\\/script>')

      # indentation is mandatory to beautify page source formatting
      """
            wi.vdomInit('#{@id}','#{@constructor.path}',#{propsStr},#{stateStr}#{parentStr});
      #{ (widget.getInitCode(@id) for widget in @widgetHierarchy.getChildren(this)).join('') }
      """


    debug: (method) ->
      ###
      Returns identification string of the current widget for debug purposes
      @param {string=} method - include optional "::method" suffix to the result
      @return {string}
      ###
      methodStr = if method? then "::#{ method }" else ''
      "vdom:#{ @constructor.path }(#{ @id })#{ methodStr }"


    ## old-widgets compatibility methods ##

    show: (params) ->
      ###
      Returns HTML (string) representation of the widget.
      This is old-widget compatibility method. Used to inject virtual-dom widget as a child of the old-widget.
      Params are treated as props.
      @param {Object} params
      @return {Promise.<string>}
      ###
      @props = params  if _.isObject(params)
      @renderDeepTree().then (vtree) ->
        stringify(vtree)
      .failAloud()


    browserInit: ->
      ###
      Old-widget compatibility
      ###
      Promise.resolved()


    markShown: ->
      ###
      Stub. @todo: implement right logic
      ###
      return


    setModifierClass: (cls) ->
      ###
      Old-widget compatibility
      ###
      return


    renderRootTag: (content) ->
      ###
      Old-widget compatibility
      ###
      content


    collectDeepCssListRec: (result) ->
      ###
      Recursively scans tree of widgets and collects list of required css-files.
      @param {Array.<string>} result - accumulating result array
      ###
      result.push(css)  for css in @constructor._getCssDeps()
      child.collectDeepCssListRec(result)  for child in @widgetHierarchy.getChildren(this)
      return


    ## static methods ##

    # used but the virtual-dom hyperscript template injected by the cordjs builder
    @h: h

    # @see `_initType` method
    @_initialized: false

    # @see `initialState` method
    @_initialState: null

    @initialState: (state) ->
      ###
      Sets initialState for the widget class with support of overriding and extending
       of initial state of the parent class.
      If initial state value is a function, it'll be executed whenever widget instance is created
       and it's result will be treated as a initial state value.
      @param {Object.<string, *>} state
      ###
      @_initialState ?= {}
      @_initialState = _.extend {}, @_initialState, state
      return


    @_init: ->
      ###
      Initializes some class-wide propreties and actions that must be done once for the widget class.
      @param Boolean restoreMode indicates that widget is re-creating on the browser after passing from the server
      ###
      @_initCss()  if CORD_IS_BROWSER
      @_initialized = this
      return


    @_initCss: ->
      ###
      Start to load CSS-files immediately when the first instance of the widget is instantiated on dynamically in the
       browser.
      @browser-only
      ###
      promises = (cssManager.load(cssFile) for cssFile in @_getCssDeps())
      @_cssPromise = Promise.all(promises).then =>
        # memory optimization
        @_cssPromise = Promise.resolved()
        return


    @_getCssDeps: ->
      ###
      Returns list of full paths to css-files required by this widget type
      @return {Array.<string>}
      ###
      result = []
      if @__cssInfo.deps and _.isArray(@__cssInfo.deps)
        for cssUrl in @__cssInfo.deps
          cssUrl += '.css'  if cssUrl.substr(-4) != '.css'
          cssUrl = cssUrl.slice(1)  if global.config.localFsMode
          result.push(cssUrl)
      result



  prepareInitialState = (instance) ->
    ###
    Prepares and returns initial state for the given widget instance based from @initialState class settings.
    Function-values are evaluated in context of the widget instance.
    Objects and arrays are shallow-cloned.
    @param {Widget} instance - the target widget instance
    @return {Object}
    ###
    result = {}
    cls = instance.constructor
    if cls._initialState
      for key, val of cls._initialState
        if _.isFunction(val)
          result[key] = val.call(instance)
        else if _.isObject(val)
          result[key] = _.clone(val)
        else
          result[key] = val
    result


  Widget

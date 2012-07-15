define [
  'underscore'
  'cord!/cord/core/widgetInitializer'
  'dustjs-linkedin'
  'postal'
], (_, widgetInitializer, dust, postal) ->

  requireFunction = if window? then require else requirejs

  dust.onLoad = (tmplPath, callback) ->
    if tmplPath.substr(0,1) is '/'
      tmplPath = tmplPath.substr(1)

    requireFunction ["text!" + tmplPath], (tplString) ->
      callback null, tplString

  class Widget

    # @const
    @DEFERRED = '__deferred_value__'

    # widget context
    ctx: null

    # child widgets
    children: null
    childByName: null

    path: null

    behaviourClass: null

    cssClass: null
    rootTag: 'div'

    # internals
    _renderStarted: false
    _childWidgetCounter: 0

    getPath: ->
      if @path?
        "#{ @path }"
      else
        throw "path is not defined for widget #{@constructor.name}"

    setPath: (path)  ->
      requireFunction [
        'cord-helper'
      ], (cordHelper) =>
        @path = cordHelper.getPathToWidget path


    resetChildren: ->
      @children = []
      @childByName = {}
      @childById = {}
      @childBindings = {}
      @_dirtyChildren = false


    constructor: (id) ->
      @_subscriptions = []
      @behaviour = null
      @resetChildren()
      @ctx = new Context(id ? (if window? then 'brow' else 'node') + '-wdt-' + _.uniqueId())

    clean: ->
      @cleanChildren()
      if @behaviour?
        @behaviour.clean()
        delete @behaviour
      subscription.unsubscribe() for subscription in @_subscriptions
      @_subscriptions = []

    loadContext: (ctx) ->
      @ctx = new Context(ctx)

    addSubscription: (subscription) ->
      @_subscriptions.push subscription

    #
    # Main method to call if you want to show rendered widget template
    # @public
    # @final
    #
    show: (params, callback) ->
      @showAction 'default', params, callback

    showJson: (params, callback) ->
      @jsonAction 'default', params, callback


    showAction: (action, params, callback) ->
      @["_#{ action }Action"] params, =>
        @renderTemplate callback

    jsonAction: (action, params, callback) ->
      @["_#{ action }Action"] params, =>
        @renderJson callback

    fireAction: (action, params) ->
      @["_#{ action }Action"] params, ->


    ###
      Action that generates/modifies widget context according to the given params
      Should be overriden in particular widget
      @private
      @param Map params some arbitrary params for the action
      @param Function callback callback function that must be called after action completion
    ###
    _defaultAction: (params, callback) ->
      callback()

    renderJson: (callback) ->
      callback null, JSON.stringify(@ctx)


    getTemplatePath: ->
      className = @constructor.name
      "#{ @path }#{ className.charAt(0).toLowerCase() + className.slice(1) }.html"


    cleanChildren: ->
      widget.clean() for widget in @children
      @resetChildren()

    renderTemplate: (callback) ->

      tmplPath = @getTemplatePath()

      tmplPath = "cord-t!#{ @path }"
      
      if dust.cache[tmplPath]?
        console.log "renderTemplate #{ tmplPath }"
        @markRenderStarted()
        if @_dirtyChildren
          @cleanChildren()
        dust.render tmplPath, @getBaseContext().push(@ctx), callback
        @markRenderFinished()

      else

        dustCompileCallback = (err, data) =>
          if err then throw err
          dust.loadSource(dust.compile data, tmplPath)
          @renderTemplate callback

        requireFunction [tmplPath], (tplString) ->
          dustCompileCallback null, tplString


    getInitCode: (parentId) ->
      parentStr = if parentId? then ", '#{ parentId }'" else ''

      namedChilds = {}
      for name, widget of @childByName
        namedChilds[widget.ctx.id] = name

      """
      wi.init('#{ @getPath() }', #{ JSON.stringify @ctx }, #{ JSON.stringify namedChilds }, #{ JSON.stringify @childBindings }#{ parentStr });
      #{ widget.getInitCode(@ctx.id) for widget in @children }
      """


    registerChild: (child, name) ->
      @children.push child
      @childByName[name] = child if name?

    getBehaviourClass: ->
      if not @behaviourClass?
        @behaviourClass = "#{ @path },Behaviour"

      if @behaviourClass == false
        null
      else
        @behaviourClass

    # @browser-only
    initBehaviour: ->
      if @behaviour?
        @behaviour.clean()
        delete @behaviour

      behaviourClass = @getBehaviourClass()
      console.log 'initBehaviour', @constructor.name, behaviourClass
      if behaviourClass?
        require ["cord-w!#{ behaviourClass }"], (BehaviourClass) =>
          @behaviour = new BehaviourClass @

    #
    # Almost copy of widgetInitializer::init but for client-side rendering
    # @browser-only
    #
    browserInit: ->
      for widgetId, bindingMap of @childBindings
        for ctxName, paramName of bindingMap
          subscription = postal.subscribe
            topic: "widget.#{ @ctx.id }.change.#{ ctxName }"
            callback: (data) =>
              params = {}
              params[paramName] = data.value
              console.log "push binding event of parent #{ @constructor.name}(#{ @ctx.id }) field #{ ctxName } for child widget #{ @childById[widgetId].constructor.name }::#{ widgetId }::#{ paramName }"
              @childById[widgetId].fireAction 'default', params
          @childById[widgetId].addSubscription subscription

      for childWidget in @children
        childWidget.browserInit()

      @initBehaviour()


    markRenderStarted: ->
      @_renderInProgress = true

    markRenderFinished: ->
      @_renderInProgress = false
      @_dirtyChildren = true
      if @_childWidgetCounter == 0
        postal.publish "widget.#{ @ctx.id }.render.children.complete", {}

    childWidgetAdd: ->
      @_childWidgetCounter++

    childWidgetComplete: ->
      @_childWidgetCounter--
      if @_childWidgetCounter == 0 and not @_renderInProgress
        postal.publish "widget.#{ @ctx.id }.render.children.complete", {}


    # should not be used directly, use getBaseContext() for lazy loading
    _baseContext: null

    getBaseContext: ->
      @_baseContext ? (@_baseContext = @_buildBaseContext())

    _buildBaseContext: ->
      dust.makeBase

        # widget-block
        widget: (chunk, context, bodies, params) =>
          @childWidgetAdd()
          chunk.map (chunk) =>

            requireFunction ["#{ params.type }"], (WidgetClass) =>

              widget = new WidgetClass
              widget.setPath params.type

              @children.push widget
              @childByName[params.name] = widget if params.name?
              @childById[widget.ctx.id] = widget

              showCallback = =>
                widget.show params, (err, output) =>

                  classAttr = if params.class then params.class else if widget.cssClass then widget.cssClass else ""
                  classAttr = if classAttr then "class=\"#{ classAttr }\"" else ""

                  @childWidgetComplete()
                  if err then throw err
                  chunk.end "<#{ widget.rootTag } id=\"#{ widget.ctx.id }\"#{ classAttr }>#{ output }</#{ widget.rootTag }>"

              waitCounter = 0
              waitCounterFinish = false

              bindings = {}

              # waiting for parent's necessary context-variables availability before rendering widget...
              for name, value of params
                if name != 'name' and name != 'type'
                  if value.charAt(0) == '!'
                    value = value.slice 1
                    bindings[value] = name
                    # if context value is deferred, than waiting asyncronously...
                    if @ctx.isDeferred value
                      waitCounter++
                      postal.subscribe
                        topic: "widget.#{ @ctx.id }.change.#{ value }"
                        callback: (data) ->
                          params[name] = data.value
                          waitCounter--
                          if waitCounter == 0 and waitCounterFinish
                            showCallback()
                    # otherwise just getting it's value syncronously
                    else
                      params[name] = @ctx[value]

              # todo: potentially not cross-browser code!
              if Object.keys(bindings).length != 0
                @childBindings[widget.ctx.id] = bindings

              waitCounterFinish = true
              if waitCounter == 0
                showCallback()
        cordI: (chunk, context, bodies, params) =>

          path = @path
          pathParts = path.split('!')

          if pathParts.length > 1 and path.substr(0, 4) is 'cord'
            path = "cord-path!#{ pathParts.slice(1).join('!') }"
          else
            path = "cord-path!#{ path }"

          chunk.map (chunk) =>
            requireFunction ["#{ path }i/#{ params.src }"], (path) =>
              chunk.end path



        deferred: (chunk, context, bodies, params) =>
          deferredKeys = params.params.split /[, ]/
          needToWait = (name for name in deferredKeys when @ctx.isDeferred name)

          # there are deferred params, handling block async...
          if needToWait.length > 0
            chunk.map (chunk) =>
              waitCounter = 0
              waitCounterFinish = false

              for name in needToWait
                if @ctx.isDeferred name
                  waitCounter++
                  postal.subscribe
                    topic: "widget.#{ @ctx.id }.change.#{ name }"
                    callback: (data) ->
                      waitCounter--
                      if waitCounter == 0 and waitCounterFinish
                        showCallback()

              waitCounterFinish = true
              if waitCounter == 0
                showCallback()

              showCallback = ->
                chunk.render bodies.block, context
                chunk.end()
          # no deffered params, parsing block immedialely
          else
            chunk.render bodies.block, context



        # widget initialization script generator
        widgetInitializer: (chunk, context, bodies, params) ->
          chunk.map (chunk) ->
            postal.subscribe
              topic: "widget.#{ widgetInitializer.rootWidget.ctx.id }.render.children.complete"
              callback: ->
                chunk.end widgetInitializer.getTemplateCode()


  class Context

    constructor: (arg) ->
      if typeof arg is 'object'
        for key, value of arg
          @[key] = value
      else
        @id = arg

    set: (args...) ->
      triggerChange = false
      if args.length == 0
        throw "Invalid number of arguments! Should be 1 or 2."
      else if args.length == 1
        pairs = args[0]
        if typeof pairs is 'object'
          for key, value of pairs
            if @setSingle key, value
              triggerChange = true
        else
          throw "Invalid argument! Single argument must be key-value pair (object)."
      else if @setSingle args[0], args[1]
        triggerChange = true

      if triggerChange
        setTimeout =>
          postal.publish "widget.#{ @id }.someChange", {}
        , 0


    setSingle: (name, newValue) ->
      triggerChange = false
      if @[name]?
        oldValue = @[name]
        if oldValue != newValue
          triggerChange = true
      else
        triggerChange = true

      @[name] = newValue

      if triggerChange
        setTimeout =>
          postal.publish "widget.#{ @id }.change.#{ name }",
            name: name
            value: newValue
        , 0

      triggerChange


    setDeferred: (args...) ->
      (@[name] = Widget.DEFERRED) for name in args

    isDeferred: (name) ->
      @[name] is Widget.DEFERRED


  Widget
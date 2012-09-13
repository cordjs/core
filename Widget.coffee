define [
  'underscore'
  'cord!/cord/core/widgetInitializer'
  'dustjs-linkedin'
  'postal'
  'cord-helper'
  'cord-s'
  'cord!isBrowser'
], (_, widgetInitializer, dust, postal, cordHelper, cordCss, isBrowser) ->

  dust.onLoad = (tmplPath, callback) ->
    require ["cord-t!" + tmplPath], (tplString) ->
      callback null, tplString


  class Widget

    #
    # Enable special mode for building structure tree of widget
    #
    compileMode: false

    # @const
    @DEFERRED: '__deferred_value__'

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
      require [
        'cord-helper'
      ], (cordHelper) =>
        @path = cordHelper.getPathToWidget path

    setCurrentBundle: (path) ->
      require [
        'cord-helper'
      ], (cordHelper) =>
        @path = cordHelper.getPathToWidget path if ! @path?
        @pathBundle = cordHelper.getPathToBundle path
        require.config
          paths:
            'currentBundle': @pathBundle


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
      @ctx = new Context(id ? (if isBrowser? then 'brow' else 'node') + '-wdt-' + _.uniqueId())
      @placeholders = {}

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
      "#{ @pathBundle }#{ @path }#{ className.charAt(0).toLowerCase() + className.slice(1) }.html"


    cleanChildren: ->
      widget.clean() for widget in @children
      @resetChildren()

    renderTemplate: (callback) ->

      tmplPath = "cord-t!#{ @path }"

      if dust.cache[tmplPath]?
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

        require [tmplPath], (tplString) =>
          ## Этот хак позволяет не виснуть dustJs.
          # зависание происходит при {#deffered}..{#name}{>"//folder/file.html"/}
          setTimeout =>
            dustCompileCallback null, tplString
          , 200

    getInitCode: (parentId) ->
      parentStr = if parentId? then ", '#{ parentId }'" else ''

      namedChilds = {}
      for name, widget of @childByName
        namedChilds[widget.ctx.id] = name

      """
      wi.init('#{ @getPath() }', #{ JSON.stringify @ctx }, #{ JSON.stringify namedChilds }, #{ JSON.stringify @childBindings }#{ parentStr });
      #{ (widget.getInitCode(@ctx.id) for widget in @children).join '' }
      """

    # include all css-files, if rootWidget init
    getInitCss: (parentId) ->
      html = ""

      if @css? and typeof @css is 'object'
        html = (cordCss.getHtml "cord-s!#{ css }" for css in @css).join ''
      else if @css?
        html = cordCss.getHtml @path, true

      """#{ html }#{ (widget.getInitCss(@ctx.id) for widget in @children).join '' }"""


    # browser-only, include css-files widget
    getWidgetCss: ->

      if @css? and typeof @css is 'object'
        cordCss.insertCss "cord-s!#{ css }" for css in @css
      else if @css?
        cordCss.insertCss @path, true


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
      if behaviourClass?
        require ["cord-w!#{ behaviourClass }"], (BehaviourClass) =>
          @behaviour = new BehaviourClass @

      @getWidgetCss()

    #
    # Almost copy of widgetInitializer::init but for client-side rendering
    # @browser-only
    #
    browserInit: ->
      for widgetId, bindingMap of @childBindings
        for ctxName, paramName of bindingMap
          widgetInitializer.subscribePushBinding @ctx.id, ctxName, @childById[widgetId], paramName

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


    subscribeValueChange: (params, name, value, callback) ->
      postal.subscribe
        topic: "widget.#{ @ctx.id }.change.#{ value }"
        callback: (data) ->
          # param with name "params" is a special case and we should expand the value as key-value pairs
          # of widget's params
          if name == 'params'
            if _.isObject data.value
              for subName, subValue of data.value
                params[subName] = subValue
            else
              # todo: warning?
          else
            params[name] = data.value
          callback()

    _buildBaseContext: ->
      if @compileMode
        @_buildCompileBaseContext()
      else
        @_buildNormalBaseContext()

    _buildNormalBaseContext: ->
      dust.makeBase

        #
        # Widget-block
        #
        widget: (chunk, context, bodies, params) =>
          @childWidgetAdd()
          console.log "childWidgetAdd (#{ @_childWidgetCounter }) #{ @constructor.name } -> #{ params.type }"
          console.log "Widget plugin before map #{ @constructor.name } -> #{ params.type }"
          chunk.map (chunk) =>

            if !params.type
              params.type = @ctx[params.getType]
              params.name = @ctx[params.getType]

            console.log "Widget plugin in map #{ @constructor.name } -> #{ params.type }"

            require [
              "cord-w!#{ params.type }"
              "cord-helper!#{ params.type }"
            ], (WidgetClass, cordHelper) =>

              widget = new WidgetClass
              widget.setPath cordHelper

              @children.push widget
              @childByName[params.name] = widget if params.name?
              @childById[widget.ctx.id] = widget

              showCallback = =>
                widget.show params, (err, output) =>

                  classAttr = if params.class then params.class else if widget.cssClass then widget.cssClass else ""
                  classAttr = if classAttr then "class=\"#{ classAttr }\"" else ""

                  @childWidgetComplete()
                  if err then throw err

                  if bodies.block?
                    tmpName = "tmp#{ _.uniqueId() }"
                    dust.register tmpName, bodies.block
                    dust.render tmpName, context, (err, out) =>
                      console.log out
                      chunk.end "<#{ widget.rootTag } id=\"#{ widget.ctx.id }\"#{ classAttr }>#{ output }</#{ widget.rootTag }>"
                  else
                    chunk.end "<#{ widget.rootTag } id=\"#{ widget.ctx.id }\"#{ classAttr }>#{ output }</#{ widget.rootTag }>"

              waitCounter = 0
              waitCounterFinish = false

              bindings = {}

              # waiting for parent's necessary context-variables availability before rendering widget...
              for name, value of params
                if name != 'name' and name != 'type'

                  if value.charAt(0) == '^'
                    value = value.slice 1
                    bindings[value] = name

                    # if context value is deferred, than waiting asyncronously...
                    if @ctx.isDeferred value
                      waitCounter++
                      @subscribeValueChange params, name, value, =>
                        waitCounter--
                        if waitCounter == 0 and waitCounterFinish
                          showCallback()

                    # otherwise just getting it's value syncronously
                    else
                      # param with name "params" is a special case and we should expand the value as key-value pairs
                      # of widget's params
                      console.log "#{ name } = \"^#{ value }\" ( -> #{ @ctx.value })"
                      if name == 'params'
                        if _.isObject @ctx[value]
                          for subName, subValue of @ctx[value]
                            params[subName] = subValue
                        else
                          # todo: warning?
                      else
                        params[name] = @ctx[value]

              # todo: potentially not cross-browser code!
              if Object.keys(bindings).length != 0
                @childBindings[widget.ctx.id] = bindings

              waitCounterFinish = true
              if waitCounter == 0
                showCallback()


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


        #
        # Widget initialization script generator
        #
        widgetInitializer: (chunk, context, bodies, params) ->
          chunk.map (chunk) ->
            postal.subscribe
              topic: "widget.#{ widgetInitializer.rootWidget.ctx.id }.render.children.complete"
              callback: ->
                chunk.end widgetInitializer.getTemplateCode()


        # css inclide
        css: (chunk, context, bodies, params) ->
          chunk.map (chunk) ->
            postal.subscribe
              topic: "widget.#{ widgetInitializer.rootWidget.ctx.id }.render.children.complete"
              callback: ->
                chunk.end widgetInitializer.getTemplateCss()


    #
    # Dust plugins for compilation mode
    #
    _buildCompileBaseContext: ->
      dust.makeBase

        #
        # Widget-block (compile mode)
        #
        widget: (chunk, context, bodies, params) =>
          console.log "Compile mode widget plugin before map #{ @constructor.name } -> #{ params.type }"
          chunk.map (chunk) =>

            if !params.type
              params.type = @ctx[params.getType]
              params.name = @ctx[params.getType]

            require [
              "cord-w!#{ params.type }"
              "cord-helper!#{ params.type }"
              "cord!widgetCompiler"
            ], (WidgetClass, cordHelper, widgetCompiler) =>

              widget = new WidgetClass
              widget.compileMode = true
              widget.setPath cordHelper

              @children.push widget
              @childByName[params.name] = widget if params.name?
              @childById[widget.ctx.id] = widget

              if bodies.block?
                widgetCompiler.addLayoutCall widget, params

              if context.surroundingWidget?
                ph = params.placeholder ? 'default'
                sw = context.surroundingWidget

                if sw.placeholders[ph]?
                  delete params.placeholder
                  delete params.type
                  widgetCompiler.addPlaceholderContent sw, ph, widget, params
                else
                  throw "there is no placeholder with id \"#{ ph }\" in surrounding widget #{ sw.constructor.name } (id = #{ sw.ctx.id })!"
              else
                # ???

              widget.renderTemplate (err, output) =>
                if err then throw err

                if bodies.block?
                  ctx = @getBaseContext().push(@ctx)
                  ctx.surroundingWidget = widget

                  tmpName = "tmp#{ _.uniqueId() }"
                  dust.register tmpName, bodies.block
                  dust.render tmpName, ctx, (err, out) =>
                    if err then throw err
                    chunk.end "<widget type=\"#{ params.type }\">#{ out }</widget>"
                else
                  chunk.end "<widget type=\"#{ params.type }\"></widget>"

        #
        # Inline - block of sub-template to place into surrounding widget's placeholder (compiler only)
        #
        inline: (chunk, context, bodies, params) =>
          chunk.map (chunk) =>
            require ['cord!widgetCompiler'], (widgetCompiler) =>
              if bodies.block?
                id = params?.id ? _.uniqueId()
                if context.surroundingWidget?
                  ph = params?.placeholder ? 'default'

                  sw = context.surroundingWidget
                  if sw.placeholders[ph]?
                    templateName = "__inline_#{ id }_template.js"
                    widgetCompiler.addPlaceholderInline sw, ph, this, templateName

                    ctx = @getBaseContext().push(@ctx)
                    ctx.surroundingWidget = sw

                    tmpName = "tmp#{ _.uniqueId() }"
                    dust.register tmpName, bodies.block

                    dust.render tmpName, ctx, (err, out) =>
                      if err then throw err
                      chunk.end "<inline type=\"#{ @constructor.name }\">#{ out }</inline>"

                  else
                    throw "there is no placeholder with id \"#{ ph }\" in surrounding widget #{ sw.constructor.name } (id = #{ sw.ctx.id })!"
                else
                  throw "inlines are not allowed outside surrounding widget (widget #{ @constructor.name }, id"
              else
                console.log "Warning: empty inline in widget #{ @constructor.name }(#{ @ctx.id })"

        #
        # Placeholder - point of extension of the widget (compiler version)
        #
        placeholder: (chunk, context, bodies, params) =>
          id = params?.id ? 'default'
          if @placeholders[id]?
            throw "duplicate placeholder id (#{ id }) for widget #{ @constructor.name }"
          @placeholders[id] = []
          chunk.write "<placeholder id=\"#{ id }\" />"
          #chunk.write "<div id=\"ph-#{ @ctx.id }-#{ id }\"></div>"


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

      if newValue?
        if @[name]?
          oldValue = @[name]
          if oldValue != newValue
            triggerChange = true
        else
          triggerChange = true

      console.log "setSingle -> #{ name } = #{ newValue } (oldValue = #{ @[name] }) trigger = #{ triggerChange }"

      @[name] = newValue if typeof newValue != 'undefined'

      if triggerChange
        setTimeout =>
          postal.publish "widget.#{ @id }.change.#{ name }",
            name: name
            value: newValue
            oldValue: oldValue
        , 0

      triggerChange


    setDeferred: (args...) ->
      (@[name] = Widget.DEFERRED) for name in args

    isDeferred: (name) ->
      @[name] is Widget.DEFERRED


  Widget

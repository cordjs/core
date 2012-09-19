define [
  'underscore'
  'cord!/cord/core/widgetInitializer'
  'dustjs-linkedin'
  'postal'
  'cord-helper'
  'cord-s'
  'cord!isBrowser'
  'cord!StructureTemplate'
], (_, widgetInitializer, dust, postal, cordHelper, cordCss, isBrowser, StructureTemplate) ->

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
      ###
      Cleanup all internal state about child widgets.
      This method is called when performing full re-rendering of the widget.
      ###
      @children = []
      @childByName = {}
      @childById = {}
      @childBindings = {}
      @_dirtyChildren = false


    #
    # Constructor
    #
    # @param string id (optional) manual ID of the widget
    # @param boolean compileMode (optional) turn on/off compile mode
    #
    constructor: (id, compileMode) ->
      if compileMode?
        compileMode = if compileMode then true else false
      else
        if _.isBoolean id
          compileMode = id
          id = null
        else
          compileMode = false

      @compileMode = compileMode
      @_subscriptions = []
      @behaviour = null
      @resetChildren()
      if compileMode
        id = 'ref-wdt-' + _.uniqueId()
      else
        id ?= (if isBrowser then 'brow' else 'node') + '-wdt-' + _.uniqueId()
      @ctx = new Context(id)
      @placeholders = {}

    clean: ->
      ###
      Kind of destructor.

      Delete all event-subscriptions assosiated with the widget and do this recursively for all child widgets.
      This have to be called when performing full re-render of some part of the widget tree to avoid double
      subscriptions left from the dissapered widgets.
      ###
      @cleanChildren()
      if @behaviour?
        @behaviour.clean()
        delete @behaviour
      subscription.unsubscribe() for subscription in @_subscriptions
      @_subscriptions = []

    loadContext: (ctx) ->
      ###
      Manually set given context state of the widget.
      This method is used when restoring state of the widget-tree of the page on the client-side after page was
      rendered on the server-side.
      ###
      @ctx = new Context(ctx)

    addSubscription: (subscription) ->
      ###
      Register event subscription associated with the widget.

      All such subscritiptions need to be registered to be able to clean them up later (see @cleanChildren())
      ###
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
        console.log "#{ @constructor.name}::_#{ action }Action: params:", params, " context:", @ctx
        @renderTemplate callback

    jsonAction: (action, params, callback) ->
      @["_#{ action }Action"] params, =>
        @renderJson callback

    fireAction: (action, params) ->
      ###
      Just call action (change context) and do not output anything
      ###
      @["_#{ action }Action"] params, ->


    ##
    # Action that generates/modifies widget context according to the given params
    # Should be overriden in particular widget
    # @private
    # @param Map params some arbitrary params for the action
    # @param Function callback callback function that must be called after action completion
    ##
    _defaultAction: (params, callback) ->
      callback()

    renderJson: (callback) ->
      callback null, JSON.stringify(@ctx)


    getTemplatePath: ->
      className = @constructor.name
      "#{ @path }/#{ className.charAt(0).toLowerCase() + className.slice(1) }.html"


    cleanChildren: ->
      widget.clean() for widget in @children
      @resetChildren()


    compileTemplate: (callback) ->

      actualRender = =>
        @markRenderStarted()
        if @_dirtyChildren
          @cleanChildren()
        dust.render tmplPath, @getBaseContext().push(@ctx), callback
        @markRenderFinished()

      if not @compileMode
        callback 'not in compile mode', ''
      else
        tmplPath = @path

        if dust.cache[tmplPath]?
          actualRender()
        else
          # compile and load dust template

          dustCompileCallback = (err, data) =>
            if err then throw err
            dust.loadSource dust.compile(data, tmplPath)
            actualRender()

          require ["cord-t!#{ tmplPath }"], (tplString) =>
            ## Этот хак позволяет не виснуть dustJs.
            # зависание происходит при {#deffered}..{#name}{>"//folder/file.html"/}
            setTimeout =>
              dustCompileCallback null, tplString
            , 200


    renderTemplate: (callback) ->
      console.log "renderTemplate(#{ @constructor.name })"

      decideWayOfRendering = =>
        ###
        Decides wether to call extended template parsing of self-template parsing and calls it.
        This closure if to avoid duplicating.
        ###

        structTmpl = dust.cache[tmplStructureFile]

        console.warn "there is no structure template for #{ @path }" if not structTmpl.extends?

        if structTmpl.extends? and _.isArray(structTmpl.extends) and structTmpl.extends.length > 0
          # extended widget, using only structure template
          @_renderExtendedTemplate structTmpl, callback
        else
          @_renderSelfTemplate callback

      tmplStructureFile = "#{ @getTemplatePath() }.structure.json"

      if dust.cache[tmplStructureFile]?
        decideWayOfRendering()
      else
        # load structure template from json-file
        require [
          'cord!config'
          'fs'
        ], (config, fs) =>
          fs.exists "./#{ config.PUBLIC_PREFIX }/#{ tmplStructureFile}", (exists) =>
            if exists
              require ["text!#{ tmplStructureFile }"], (tplJsonString) =>
                dust.register tmplStructureFile, JSON.parse(tplJsonString)
                decideWayOfRendering()
            else
              dust.register tmplStructureFile, {}
              @_renderSelfTemplate callback


    _renderSelfTemplate: (callback) ->
      ###
      Usual way of rendering template via dust.
      ###

      console.log "_renderSelfTemplate(#{ @constructor.name})"

      actualRender = =>
        @markRenderStarted()
        if @_dirtyChildren
          @cleanChildren()
        dust.render tmplPath, @getBaseContext().push(@ctx), callback
        @markRenderFinished()

      tmplPath = @path

      if dust.cache[tmplPath]?
        actualRender()
      else
        # compile and load dust template

        dustCompileCallback = (err, data) =>
          if err then throw err
          dust.loadSource dust.compile(data, tmplPath)
          actualRender()

        require ["cord-t!#{ tmplPath }"], (tplString) =>
          ## Этот хак позволяет не виснуть dustJs.
          # зависание происходит при {#deffered}..{#name}{>"//folder/file.html"/}
          setTimeout =>
            dustCompileCallback null, tplString
          , 200

    resolveParamRefs: (widget, params, callback) ->
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
                  callback params

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
        callback params


    _renderExtendedTemplate: (struct, callback) ->
      ###
      Render template if it uses #extend plugin to extend another widget
      ###

      console.log @constructor.name, struct.rootWidget

      tmpl = new StructureTemplate struct, this

      extendWidgetInfo = tmpl.struct.extends[0]
      console.log extendWidgetInfo

      tmpl.getWidget extendWidgetInfo.widget, (extendWidget) =>
        @resolveParamRefs extendWidget, extendWidgetInfo.params, (params) ->
          extendWidget.show params, callback


    renderInlineTemplate: (template, callback) ->
      tmplPath = "#{ @getPath() }/#{ template}"
      require ["text!#{ tmplPath }"], (tmplString) =>
        x = eval tmplString
        dust.render tmplPath, @getBaseContext().push(@ctx), callback


    injectPlaceholders: (placeholders) ->
      @placeholders = placeholders


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
#          console.log "Widget plugin before map #{ @constructor.name } -> #{ params.type }"
          chunk.map (chunk) =>

#            console.log "Widget plugin in map #{ @constructor.name } -> #{ params.type }"

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
        # Placeholder - point of extension of the widget (compiler version)
        #
        placeholder: (chunk, context, bodies, params) =>
          chunk.map (chunk) =>
            id = params?.id ? 'default'

            waitCounter = 0
            waitCounterFinish = false

            placeholderOut = []
            showCallback = =>
              chunk.end "<div id=\"ph-#{ @ctx.id }-#{ id }\">#{ placeholderOut.join '' }</div>"

            for info in @placeholders[id]
              if info.type == 'widget'
                waitCounter++
                info.widget.show info.params, (err, out) ->
                  if err then throw err
                  # todo: add class attribute support
                  placeholderOut.push "<#{ info.widget.rootTag } id=\"#{ info.widget.ctx.id }\">#{ out }</#{ info.widget.rootTag }>"
                  waitCounter--
                  if waitCounter == 0 and waitCounterFinish
                    showCallback()
              else
                waitCounter++
                info.widget.renderInlineTemplate info.template, (err, out) ->
                  if err then throw err
                  placeholderOut.push "<div class=\"cord-inline\">#{ out }</div>"
                  waitCounter--
                  if waitCounter == 0 and waitCounterFinish
                    showCallback()

            waitCounterFinish = true
            if waitCounter == 0
              showCallback()

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

        extend: (chunk, context, bodies, params) =>
          ###
          Extend another widget (probably layout-widget).

          This section should be used as a root element of the template and all contents should be inside it's body
          block. All contents outside this section will be ignored. Example:

              {#extend type="//rootLayout" someParam="foo"}
                {#widget type="//mainMenu" selectedItem=activeItem placeholder="default"/}
              {/extend}

          This section accepts the same params as the "widget" section, except of placeholder which logically cannot
          be used with extend.

          todo: add check of (un)existance of other root sections in the template
          ###

          console.log "Extend plugin before map #{ @constructor.name } -> #{ params.type }"
          chunk.map (chunk) =>

            if not params.type? or !params.type
              throw "Extend must have 'type' param defined!"

            if params.placeholder?
              console.log "WARNING: 'placeholder' param is useless for 'extend' section"

            require [
              "cord-w!#{ params.type }"
              "cord-helper!#{ params.type }"
              "cord!widgetCompiler"
            ], (WidgetClass, cordHelper, widgetCompiler) =>

              widget = new WidgetClass @compileMode
              widget.setPath cordHelper

              widgetCompiler.addExtendCall widget, params

              if bodies.block?
                ctx = @getBaseContext().push(@ctx)
                ctx.surroundingWidget = widget

                tmpName = "tmp#{ _.uniqueId() }"
                dust.register tmpName, bodies.block
                dust.render tmpName, ctx, (err, out) =>
                  if err then throw err
                  chunk.end ""
              else
                console.log "WARNING: Extending widget #{ params.type } with nothing!"
                chunk.end ""

        #
        # Widget-block (compile mode)
        #
        widget: (chunk, context, bodies, params) =>
          console.log "Compile mode widget plugin before map #{ @constructor.name } -> #{ params.type }"
          chunk.map (chunk) =>

            require [
              "cord-w!#{ params.type }"
              "cord-helper!#{ params.type }"
              "cord!widgetCompiler"
            ], (WidgetClass, cordHelper, widgetCompiler) =>

              widget = new WidgetClass @compileMode
              widget.setPath cordHelper

              @children.push widget
              @childByName[params.name] = widget if params.name?
              @childById[widget.ctx.id] = widget

              if context.surroundingWidget?
                ph = params.placeholder ? 'default'
                sw = context.surroundingWidget

                delete params.placeholder
                delete params.type
                widgetCompiler.addPlaceholderContent sw, ph, widget, params
              else
                # ???

              if bodies.block?
                ctx = @getBaseContext().push(@ctx)
                ctx.surroundingWidget = widget

                tmpName = "tmp#{ _.uniqueId() }"
                dust.register tmpName, bodies.block
                dust.render tmpName, ctx, (err, out) =>
                  if err then throw err
                  chunk.end ""
              else
                chunk.end ""

        #
        # Inline - block of sub-template to place into surrounding widget's placeholder (compiler only)
        #
        inline: (chunk, context, bodies, params) =>
          chunk.map (chunk) =>
            require [
              'cord!widgetCompiler'
              'fs'
              'cord!config'
            ], (widgetCompiler, fs, config) =>
              if bodies.block?
                id = params?.id ? _.uniqueId()
                if context.surroundingWidget?
                  ph = params?.placeholder ? 'default'

                  sw = context.surroundingWidget

                  templateName = "__inline_template_#{ id }.html.js"
                  tmplPath = "#{ @getPath() }/#{ templateName }"
                  tmplFullPath = "./#{ config.PUBLIC_PREFIX }/#{ tmplPath }"

                  tmplString = "(function(){dust.register(\"#{ tmplPath }\", #{ bodies.block.name }); #{ bodies.block.toString() }; return #{ bodies.block.name };})();"

                  fs.writeFile tmplFullPath, tmplString, (err)->
                    console.log 'function-name: ', bodies.block.name, dust.compile("Hello {name}!", "intro");
                    if err then throw err
                    console.log "template saved #{ tmplFullPath }"

                  widgetCompiler.addPlaceholderInline sw, ph, this, templateName

                  ctx = @getBaseContext().push(@ctx)
                  ctx.surroundingWidget = sw

                  tmpName = "tmp#{ _.uniqueId() }"
                  dust.register tmpName, bodies.block

                  dust.render tmpName, ctx, (err, out) =>
                    if err then throw err
                    chunk.end ""

                else
                  throw "inlines are not allowed outside surrounding widget (widget #{ @constructor.name }, id"
              else
                console.log "Warning: empty inline in widget #{ @constructor.name }(#{ @ctx.id })"



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

#      console.log "setSingle -> #{ name } = #{ newValue } (oldValue = #{ @[name] }) trigger = #{ triggerChange }"

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

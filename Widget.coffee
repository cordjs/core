define [
  'cord!Collection'
  'cord!Context'
  'cord!css/helper'
  'cord!errors'
  'cord!helpers/TimeoutStubHelper'
  'cord!isBrowser'
  'cord!Model'
  'cord!Module'
  'cord!StructureTemplate'

  'cord!templateLoader'
  'cord!Utils'
  'cord!utils/DomInfo'
  'cord!utils/Future'

  'dustjs-helpers'
  'monologue' + (if CORD_IS_BROWSER then '' else '.js')
  'postal'
  'underscore'
], (Collection, Context, cssHelper, errors, TimeoutStubHelper, isBrowser, Model, Module, StructureTemplate,
    templateLoader, Utils, DomInfo, Future,
    dust, Monologue, postal, _) ->

  dust.onLoad = (tmplPath, callback) ->
    templateLoader.loadTemplate tmplPath, ->
      callback null, ''


  class Widget extends Module
    @include Monologue.prototype


    # widget repository
    widgetRepo = null

    # service container
    container = null

    # widget context
    ctx: null

    # child widgets
    children: null
    childByName: null
    childById: null

    behaviourClass: null
    behaviour: null

    cssClass: null
    rootTag: 'div'

    # internals
    _renderStarted: false
    _childWidgetCounter: 0

    _structTemplate: null
    _isExtended: false

    # should not be used directly, use getBaseContext() for lazy loading
    _baseContext: null

    _modelBindings: null

    _placeholdersClasses: null

    # promise needed to prevent setParams() to be applied while template rendering is performed
    # it just holds renderTemplate() method return value
    _renderPromise: null

    # promise to load widget completely (with all styles and behaviours, including children)
    _widgetReadyPromise: null
    # indicates that browserInit was already called. Initially should be true
    # and reset in certain places via _resetWidgetReady() method
    _browserInitialized: true

    # promise that resolves when the widget is actually shown in the DOM
    _shownPromise: null
    _shown: false

    # temporary helper data container for inline-block processing
    _inlinesRuntimeInfo: null

    # list of placeholders render information including deep placeholders of immediate-included widgets
    # deep infomation is need by replacePlaceholders() to include child widgets and inlines correctly
    _placeholdersRenderInfo: null

    # Object of subscibed push binding (by parent widget context's param name)
    _subscibedPushBindings: null

    # Behaviuor's event handler duplication prevention temporary map. Used in the widget's behaviuor class.
    _eventCursors: null


    @_initParamRules: ->
      ###
      Prepares rules for handling incoming params of the widget.
      Converts params static attribute of the class into _paramRules array which defines behaviour of setParams()
       method of the widget.
      ###

      handleStringCallback = (rule, methodName) =>
        if @prototype[methodName]
          callback =  @prototype[methodName]
          if _.isFunction callback
            rule.callback = callback
          else
            throw new Error("Callback #{ methodName } is not a function")
        else
          throw new Error("#{ methodName } doesn't exist")

      @_paramRules = {}
      for param, info of @params
        rule = {}

        if _.isFunction info
          rule.type = ':callback'
          rule.callback = info
        else if _.isString info
          if info.charAt(0) == ':'
            if info == ':ctx'
              rule.type = ':setSame'
            else if info.substr(0, 5) == ':ctx.'
              rule.type = ':set'
              rule.ctxName = info.trim().substr(5)
            else if info == ':ignore'
              rule.type = ':ignore'
            else
              throw "Invalid special string value for param '#{ param }': #{ info }!"
          else
            rule.type = ':callback'
            handleStringCallback(rule, info)
        else if _.isObject info
          if info.callback?
            rule.type = ':callback'
            if _.isString info.callback
              handleStringCallback(rule, info.callback)
            else if _.isFunction info.callback
              rule.callback = info.callback
          else if info.set
            rule.type = ':set'
            rule.ctxName = info.set
          else
            rule.type = ':setSame'

        splittedParams = param.trim().split(/\s*,\s*/)
        rule.id = splittedParams.join ','
        if splittedParams.length > 1
          rule.multiArgs = true
          rule.params = splittedParams
        for name in splittedParams
          @_paramRules[name] ?= []
          @_paramRules[name].push rule


    @_parseChildEvents: ->
      ###
      Converts child widget subscriptions form @childEvents into optimized three-level map:
       childName -> topic -> callbacks.
      This map is used later to bind child events when children are attached to the widgets of this type.
      This conversion is performed only once for the whole widget class.
      ###
      @_childEventSubscriptions = {}
      if @childEvents
        for eventDef, callback of @childEvents
          [childName, topic] = eventDef.split(' ')
          if _.isString(callback)
            if @::[callback]
              callback = @::[callback]
            else
              throw new Error("Child event callback name '#{callback}' is not a member of #{@__name}!")
          if not _.isFunction(callback)
            throw new Error("Invalid child widget callback definition: #{@__name}::[#{childName}, #{topic}]!")

          @_childEventSubscriptions[childName] ?= {}
          @_childEventSubscriptions[childName][topic] ?= []
          @_childEventSubscriptions[childName][topic].push(callback)
        @childEvents = undefined


    @_initCss: (restoreMode) ->
      ###
      Start to load CSS-files immediately when the first instance of the widget is instantiated on dynamically in the
       browser.
      @browser-only
      ###
      @_cssPromise =
        if not restoreMode
          Future.require('cord!css/browserManager').then (cssManager) =>
            promises = (cssManager.load(cssFile) for cssFile in @::getCssFiles())
            Future.sequence(promises)
        else
          Future.resolved()


    getPath: ->
      @constructor.path


    getName: ->
      @constructor.__name


    getDir: ->
      @constructor.relativeDirPath


    getBundle: ->
      @constructor.bundle


    @_initialized: false

    @_init: (restoreMode) ->
      ###
      Initializes some class-wide propreties and actions that must be done once for the widget class.
      @param Boolean restoreMode indicates that widget is re-creating on the browser after passing from the server
      ###
      if @params?
        @_initParamRules()
      @_parseChildEvents()
      @_initCss(restoreMode) if isBrowser
      @_rawStructPromise = undefined
      @_initialized = this


    constructor: (params) ->
      ###
      Constructor

      Accepted params:
      * context (Object) - inject widget's context explicitly (should re used only to restore widget's state on node-browser
                           transfer
      * repo (WidgetRepo) - inject widget repository (should be always set except in compileMode
      * compileMode (boolean) - turn on/off special compile mode of the widget (default - false)
      * extended (boolean) - mark widget as part of extend tree (default - false)
      * restoreMode(boolean) - hint pointing that it's a recreation of the widget while passing from server to browser
                               helpful to make few optimizations

      @param (optional)Object params custom params, accepted by widget
      ###
      @constructor._init(params.restoreMode) if @constructor._initialized != @constructor # detects widget inheritance

      @_modelBindings = {}
      @_subscibedPushBindings = {}
      @_eventCursors = {}
      compileMode = false
      if params?
        if params.context?
          if params.context instanceof Context
            @ctx = params.context
          else
            @ctx = new Context(params.context)
            @ctx.setOwnerWidget(this)
        @setRepo params.repo if params.repo?
        @setServiceContainer params.serviceContainer if params.serviceContainer?
        compileMode = params.compileMode if params.compileMode?
        @_isExtended = params.extended if params.extended?
        if params.modelBindings?
          @_modelBindings = params.modelBindings
          @_initModelsEvents() if isBrowser

      @_postalSubscriptions = []
      @_tmpSubscriptions = []
      @_placeholdersClasses = {}

      @resetChildren()

      if not @ctx?
        if compileMode
          id = 'rwdt-' + _.uniqueId()
        else
          id = (if isBrowser then 'b' else 'n') + 'wdt-' + _.uniqueId()
        @ctx = new Context(id, Utils.cloneLevel2(@constructor.initialCtx))
        @ctx.setOwnerWidget(this)

      if isBrowser
        @_browserInitialized = true
        @_widgetReadyPromise = Future.single(@debug('_widgetReadyPromise.resolved')).resolve()
        @_shownPromise = Future.single('Widget::_shownPromise ' + @constructor.__name)

        # Restoring translator helper by saved context
        if @ctx.i18nHelper
          i18nContext = @ctx.i18nHelper
          @ctx.i18nHelper = (text, params) =>
            params.context = i18nContext if not params.context
            @translator.translate2(text, params)

      @_renderPromise = Future.resolved()

      @_callbacks = []
      @_promises = []


    clean: ->
      ###
      Kind of destructor.
      Deletes all event-subscriptions associated with the widget and do this recursively for all child widgets.
      This have to be called when performing full re-render of some part of the widget tree to avoid double
      subscriptions left from the disappeared widgets.
      ###
      @_sentenced = true
      @cleanChildren()
      @_cleanBehaviour()
      @cleanSubscriptions()
      @cleanTmpSubscriptions()
      @cleanModelSubscriptions()
      @_modelBindings = null
      @_subscibedPushBindings = null
      @clearCallbacks()
      @off() #clean monologue subscriptions
      @_cleanPromises()
      if @_shownPromise?
        @_shownPromise.clear()
        @_shownPromise = null
      @ctx.clearDeferredTimeouts()
      if @_widgetReadyPromise
        if not @_browserInitialized and not @_widgetReadyPromise.completed()
          @_widgetReadyPromise.reject(new errors.WidgetDropped("Widget #{@constructor.__name} is cleaned!"))
          @_widgetReadyPromise.clear()
        else
          @_widgetReadyPromise.clear()
          @_widgetReadyPromise = Future.rejected(new errors.WidgetDropped('widget is cleaned!'))
          @_widgetReadyPromise.clear()


    _cleanBehaviour: ->
      ###
      Correctly cleans behaviour. DRY
      ###
      if @behaviour?
        @behaviour.clean()
        @behaviour = null

      if @_browserInitDebugTimeout?
        clearTimeout(@_browserInitDebugTimeout)
        @_browserInitDebugTimeout = null


    getCallback: (callback) ->
      ###
      Register callback and clear it in case of object destruction or clearCallbacks invocation
      Need to be used, when reference to the widget object (@) is used inside a callback, for instance:
      api.get Url, Params, @getCallback (result) =>
        @ctx.set 'apiResult', result
      ###
      makeSafeCallback = (callback) ->
        result = ->
          if !result.cleared
            callback.apply(this, arguments)
        result.cleared = false

        result

      safeCallback = makeSafeCallback(callback)
      @_callbacks.push safeCallback
      safeCallback


    clearCallbacks: ->
      ###
      Clear registered callbacks
      ###
      callback.cleared = true for callback in @_callbacks
      @_callbacks = []


    createPromise: (initialCounter = 0, name = '') ->
      promise = new Future initialCounter, name
      @_promises.push promise
      promise


    addPromise: (promise) ->
      @_promises.push promise
      promise


    _cleanPromises: ->
      promise.clear() for promise in @_promises
      @_promises = []


    addSubscription: (subscription, callback = null) ->
      ###
      Register event subscription associated with the widget.

      Use this only for push bindings. todo: rename this method

      All such subscritiptions need to be registered to be able to clean them up later (see @cleanChildren())
      ###
      if callback and _.isString subscription
        subscription = postal.subscribe
          topic: subscription
          callback: callback

      @_postalSubscriptions.push subscription
      subscription


    cleanSubscriptions: ->
      subscription.unsubscribe() for subscription in @_postalSubscriptions
      @_postalSubscriptions = []


    addTmpSubscription: (subscription) ->
      @_tmpSubscriptions.push(subscription)


    cleanTmpSubscriptions: ->
      subscription.unsubscribe() for subscription in @_tmpSubscriptions
      @_tmpSubscriptions = []


    cleanModelSubscriptions: ->
      for name, mb of @_modelBindings
        mb.subscription?.unsubscribe()


    setRepo: (repo) ->
      ###
      Inject widget repository to create child widgets in same repository while rendering the same page.
      The approach is one repository per request/page rendering.
      @param WidgetRepo repo the repository
      ###
      @widgetRepo = repo


    setServiceContainer: (serviceContainer) ->
      @container = serviceContainer


    getServiceContainer: ->
      @container


    _registerModelBinding: (name, value) ->
      ###
      Handles situation when widget's incoming param is model of collection.
      @param String name param name
      @param Any value param value which should be checked to be model or collection and handled accordingly
      ###
      if value != undefined
        if isBrowser and @_modelBindings[name]?
          mb = @_modelBindings[name]
          if value != mb.model
            mb.subscription.unsubscribe() if mb.subscription?
            delete @_modelBindings[name]
        if value instanceof Model or value instanceof Collection
          @_modelBindings[name] ?= {}
          @_modelBindings[name].model = value

          @_bindModelParamEvents(name) if isBrowser


    _initModelsEvents: ->
      ###
      Subscribes to model events for all model-params came to widget.
      @browser-only
      ###
      for name of @_modelBindings
        @_bindModelParamEvents(name)
#      # make context to wait until widget's behaviour readiness before triggering events
#      @ctx.setEventKeeper(@ready())
#      @ready().done => @ctx.setEventKeeper(null)


    _bindModelParamEvents: (name) ->
      ###
      Subscribes the widget to the model events if param with the given name is model
      @browser-only
      @param String name widget's param name
      ###
      mb = @_modelBindings[name]
      rules = @constructor._paramRules
      if not mb.subscription? and rules[name]?
        if mb.model instanceof Model
          mb.subscription = mb.model.on 'change', (changed) =>
            for rule in rules[name]
              switch rule.type
                when ':setSame' then @ctx.set(name, changed)
                when ':set' then @ctx.set(rule.ctxName, changed)
                when ':callback'
                  if rule.multiArgs
                    (params = {})[name] = changed
                    args = (params[multiName] for multiName in rule.params)
                    rule.callback.apply(this, args)
                  else
                    rule.callback.call(this, changed)
        else if mb.model instanceof Collection
          mb.subscription = mb.model.on 'change', (changed) =>
            for rule in rules[name]
              switch rule.type
                when ':setSame' then @ctx.set(name, mb.model.toArray())
                when ':set' then @ctx.set(rule.ctxName, mb.model.toArray())
                when ':callback'
                  if rule.multiArgs
                    (params = {})[name] = mb.model
                    args = (params[multiName] for multiName in rule.params)
                    rule.callback.apply(this, args)
                  else
                    rule.callback.call(this, mb.model)


    setParamsSafe: (params) ->
      ###
      Main "reactor" to the widget's API params change from outside.
      Changes widget's context variables according to the rules, defined in "params" static configuration of the widget.
      Rules are applied only to defined input params.
      Prevents applying params to the context during widget template rendering and defers actual context modification
       to the moment after rendering. If more than one setParams() is called during template rendering then only last
       call is performed, all others are rejected.
      @param Object params changed params
      @return Future
      ###
      if @_renderPromise.completed()
        if @_sentenced
          Future.rejected(new errors.WidgetParamsRace("#{ @debug 'setParamsSafe' } is called for sentenced widget!"))
        else
          Future.try => @setParams(params)
      else
        if not @_lastSetParams?
          @_renderPromise.finally =>
            @_nextSetParamsCallback()
        else
          @_lastSetParams.reject(new errors.WidgetParamsRace("#{@debug('setParamsSafe') } overlapped with new call!"))

        @_lastSetParams = Future.single()

        @_nextSetParamsCallback = =>
          if @_sentenced
            x = new errors.WidgetParamsRace("#{ @debug('setParamsSafe') } is called for sentenced widget!")
            @_lastSetParams.reject(x)
          else
            Future.try =>
              @setParams(params)
            .link(@_lastSetParams)
          @_nextSetParamsCallback = null
          @_lastSetParams = null

        @_lastSetParams


    setParams: (params) ->
      ###
      Actual synchronous "applyer" of params for the setParams() call.
      @see setParamsSafe()
      @param Map[String -> Any] params incoming params
      @synchronous
      @throws validation errors
      ###
      _console.log "#{ @debug 'setParams' } -> ", params if global.config.debug.widget
      if @constructor.params?
        rules = @constructor._paramRules
        processedRules = {}
        specialParams = ['match', 'history', 'shim', 'trigger', 'params']
        for name, value of params
          if rules[name]?
            for rule in rules[name]
              if rule.hasValidation and not rule.validate(value)
                throw new Error("Validation of param '#{ name }' of widget #{ @debug() } is not passed!")
              else
                switch rule.type
                  when ':setSame' then @ctx.set(name, value)
                  when ':set' then @ctx.set(rule.ctxName, value)
                  when ':callback'
                    if rule.multiArgs
                      if not processedRules[rule.id]
                        args = []
                        for multiName in rule.params
                          value = params[multiName]
                          @_registerModelBinding(multiName, value)
                          args.push(value)
                        rule.callback.apply(this, args)
                        processedRules[rule.id] = true
                    else
                      @_registerModelBinding(name, value)
                      rule.callback.call(this, value)
                  when ':ignore'
                  else
                    throw new Error("Invalid param rule type: '#{ rule.type }'")
          else if specialParams.indexOf(name) == -1 and global.config.strictWidgetParams
            throw new Error("Widget #{ @getPath() } is not accepting param with name #{ name }!")
      else
        for key in params
          _console.warn "#{ @debug() } doesn't accept any params, '#{ key }' given!"


    _handleOnShow: ->
      ###
      Executes onShow-callback if it is defined for the widget and delays widget rendering if ':block' is returned.
      @return Future
      ###
      if @onShow?
        result = Future.single(@debug('_handleOnShow'))
        if @onShow(-> result.resolve()) != ':block'
          result.resolve()
        result
      else
        Future.resolved()


    show: (params, domInfo) ->
      ###
      Main method to call if you want to show rendered widget template
      @param Object params params to pass to the widget processor
      @param DomInfo domInfo DOM creating and inserting promise container
      @public
      @final
      @return Future(String)
      ###
      @setParamsSafe(params).then =>
        _console.log "#{ @debug 'show' } -> params:", params, " context:", @ctx if global.config.debug.widget
        @_handleOnShow()
      .then =>
        @renderTemplate(domInfo)


    getTemplatePath: ->
      "#{ @getDir() }/#{ @constructor.dirName }.html"


    cleanChildren: ->
      if @children.length
        if @_structTemplate? and not @_structTemplate.isEmpty()
          @_structTemplate.unassignWidget(widget) for widget in @children
        # widget.drop will mutate @children indirectly so it's better to work with clone
        widget.drop() for widget in _.clone(@children)
        @resetChildren()


    sentenceChildrenToDeath: ->
      child.sentenceToDeath() for child in @children


    sentenceToDeath: ->
      if not @_sentenced
        @cleanSubscriptions()
        @cleanModelSubscriptions()
        @_sentenced = true
        if not @_browserInitialized and not @_widgetReadyPromise.completed()
          @_widgetReadyPromise.reject(new errors.WidgetSentenced("Widget #{@constructor.__name} is sentenced!"))
      @sentenceChildrenToDeath()


    isSentenced: ->
      @_sentenced


    getStructTemplate: ->
      ###
      Loads (if neccessary) and returns in Future structure teamplate of the widget or :empty if it has no one.
      @return Future(StructureTemplate | :empty)
      ###
      if @_structTemplate?
        Future.resolved(@_structTemplate)
      else
        if not @constructor._rawStructPromise
          tmplStructureFile = "bundles/#{ @getTemplatePath() }.struct"
          @constructor._rawStructPromise = Future.require(tmplStructureFile)
        @constructor._rawStructPromise.map (struct) =>
          if struct.widgets? and Object.keys(struct.widgets).length > 1
            @_structTemplate = new StructureTemplate(struct, this)
          else
            @_structTemplate = StructureTemplate.emptyTemplate()
          @_structTemplate


    inject: (params, commonExistingWidget, transition) ->
      ###
      Injects the widget into the extend-tree and reorganizes the tree.
      Recursively walks through it's extend-widgets until matching widget is found in the current extend-tree.
      If the matching extend-widget is found then new widgets are 'attached' to it's placeholders.
      If the matching extend-widget is not eventually found then the page is reloaded to fully rebuild the DOM.
      @browser-only
      @param {Object} params
      @param {Widget} commonExistingWidget
      @param {PageTransition} transition
      @return {Future[Widget]} common base widget found in extend-tree
      ###
      _console.log "#{ @debug 'inject' }", params if global.config.debug.widget

      @setParamsSafe(params).then =>
        @getStructTemplate().zip(@_handleOnShow())
      .then (tmpl) =>

        @_resetWidgetReady()
        @_behaviourContextBorderVersion = null
        @_placeholdersRenderInfo = []
        @_deferredBlockCounter = 0

        extendWidgetInfo = if not tmpl.isEmpty() then tmpl.struct.extend else null
        if extendWidgetInfo?
          if commonExistingWidget.getPath() == tmpl.struct.widgets[extendWidgetInfo.widget].path
            extendWidget = commonExistingWidget
            readyPromise = new Future(@debug('_injectRender:readyPromise'))
            @_inlinesRuntimeInfo = []

            @resolveParamRefs(extendWidget, extendWidgetInfo.params).then (params) ->
              extendWidget.setParamsSafe(params)
            .link(readyPromise)

            tmpl.assignWidget extendWidgetInfo.widget, extendWidget

            Future.require('jquery')
              .zip(tmpl.replacePlaceholders(extendWidgetInfo.widget, extendWidget.ctx[':placeholders'], transition))
              .then ($) =>
                # if there are inlines owned by this widget
                if @_inlinesRuntimeInfo.length
                  $el = $()
                  # collect all placeholder roots with all inlines to pass to the behaviour
                  $el = $el.add(domRoot) for domRoot in @_inlinesRuntimeInfo
                else
                  $el = undefined

                @browserInit(extendWidget, $el)
                  .link(readyPromise)
                  .done => @markShown()

                readyPromise
              .then =>
                @_inlinesRuntimeInfo = null
                extendWidget

          # if not extendsWidget? (if it's a new widget in extend tree)
          else
            tmpl.getWidget(extendWidgetInfo.widget).then (extendWidget) =>
              @resolveParamRefs(extendWidget, extendWidgetInfo.params).then (params) =>
                extendWidget.inject(params, commonExistingWidget, transition)
              .then (commonBaseWidget) =>
                @browserInit(extendWidget).done => @markShown()
                commonBaseWidget
        else
          location.reload()


    renderTemplate: (domInfo) ->
      ###
      Decides wether to call extended template parsing of self-template parsing and calls it.
      @param DomInfo domInfo DOM creating and inserting promise container
      @return Future(String)
      ###
      _console.log @debug('renderTemplate') if global.config.debug.widget

      @_resetWidgetReady() # allowing to call browserInit() after template re-render is reasonable
      @_behaviourContextBorderVersion = null
      @_placeholdersRenderInfo = []
      @_deferredBlockCounter = 0

      @_renderPromise = @getStructTemplate().flatMap (tmpl) =>
        if tmpl.isExtended()
          @_renderExtendedTemplate(tmpl, domInfo)
        else
          @_renderSelfTemplate(domInfo)


    _renderSelfTemplate: (domInfo) ->
      ###
      Usual way of rendering template via dust.
      @param DomInfo domInfo DOM creating and inserting promise container
      @return Future(String)
      ###
      _console.log @debug('_renderSelfTemplate') if global.config.debug.widget

      tmplPath = @getPath()

      templateLoader.loadWidgetTemplate(tmplPath).flatMap =>
        @markRenderStarted()
        @cleanChildren()
        @_saveContextVersionForBehaviourSubscriptions()
        @_domInfo = domInfo
        result = Future.call(dust.render, tmplPath, @getBaseContext().push(@ctx))
        @markRenderFinished()
        result


    resolveParamRefs: (widget, params) ->
      ###
      Waits until child widget param values referenced using '^' sing to deferred context values are ready.
      By the way subscribes child widget to the pushing of those changed context values from the parent (this) widget.
      Completes returned promise with fully resolved map of child widget's params.
      @param Widget widget the target child widget
      @param Map[String -> Any] params map of it's params with values with unresolved references to the parent's context
      @return Future[String -> Any] resolved params
      ###
      params = _.clone(params) # this is necessary to avoid corruption of original structure template params

      # removing special params
      delete params.placeholder
      delete params.type
      delete params.class
      delete params.name
      delete params.timeout

      result = new Future(@debug('resolveParamRefs'))

      bindings = {}

      # waiting for parent's necessary context-variables availability before rendering widget...
      for name, value of params
        if name != 'name' and name != 'type'

          if typeof value is 'string' and value.charAt(0) == '^'
            value = value.slice(1) # cut leading ^
            bindings[value] = name

            # if context value is deferred, than waiting asynchronously...
            if @ctx.isDeferred(value)
              result.fork()
              do (name, value) =>
                @subscribeValueChange params, name, value, =>
                  @widgetRepo.subscribePushBinding(@ctx.id, value, widget, name, @ctx.getVersion()) if isBrowser
                  result.resolve()

            # otherwise just getting it's value synchronously
            else
              # param with name "params" is a special case and we should expand the value as key-value pairs
              # of widget's params
              if name == 'params'
                if _.isObject @ctx[value]
                  for subName, subValue of @ctx[value]
                    params[subName] = subValue
                  @widgetRepo.subscribePushBinding(@ctx.id, value, widget, 'params', @ctx.getVersion()) if isBrowser
                else
                  # todo: warning?
              else
                params[name] = @ctx[value]
                @widgetRepo.subscribePushBinding(@ctx.id, value, widget, name, @ctx.getVersion()) if isBrowser

      if Object.keys(bindings).length != 0
        @childBindings[widget.ctx.id] = bindings

      result.map -> params


    _renderExtendedTemplate: (tmpl, domInfo) ->
      ###
      Render template if it uses #extend plugin to extend another widget
      @param StructureTemplate tmpl structure template object
      @param DomInfo domInfo DOM creating and inserting promise container
      @return Future(String)
      ###
      extendWidgetInfo = tmpl.struct.extend

      tmpl.getWidget(extendWidgetInfo.widget).then (extendWidget) =>
        extendWidget._isExtended = true if @_isExtended
        @resolveParamRefs(extendWidget, extendWidgetInfo.params).then (params) ->
          extendWidget.show(params, domInfo)


    renderInline: (inlineName, domInfo) ->
      ###
      Renders widget's inline-block by name
      @param String inlineName name of the inline to render
      @param DomInfo domInfo DOM creating and inserting promise container
      @return Future(String)
      ###
      _console.log "#{ @constructor.__name }::renderInline(#{ inlineName })" if global.config.debug.widget

      if @ctx[':inlines'][inlineName]?
        tmplPath = "#{ @getDir() }/#{ @ctx[':inlines'][inlineName].template }.html"
        templateLoader.loadToDust(tmplPath).then =>
          @_saveContextVersionForBehaviourSubscriptions()
          @_domInfo = DomInfo.merge(@_domInfo, domInfo)
          Future.call(dust.render, tmplPath, @getBaseContext().push(@ctx))
      else
        Future.rejected(new Error("Trying to render unknown inline (name = #{ inlineName })!"))


    renderRootTag: (content) ->
      ###
      Builds and returns correct html-code of the widget's root tag with the given rendered contents.
      @param String content rendered template of the widget
      @return String
      ###
      classString = @_buildClassString()
      classAttr = if classString.length then ' class="' + classString + '"' else ''
      "<#{ @rootTag } id=\"#{ @ctx.id }\"#{ classAttr }#{ @_getWidgetDataAttrs() }>#{ content }</#{ @rootTag }>"


    _getWidgetDataAttrs: ->
      ###
      Builds and returns string with the given data attributes
      In debug mode adds extra widget info
      @return String data attrs
      ###
      if global.config.debug.widgetName
        @addDataAttr('widget-class-name', @getName())
        @addDataAttr('widget-class-path', @getPath())

      dataList = []
      dataList.push("data-#{key}=\"#{value}\"") for key, value of @ctx.__cord_data_attrs__ if @ctx.__cord_data_attrs__?
      dataList.join(' ')


    renderPlaceholderTag: (name, content) ->
      ###
      Wraps content with appropriate placeholder root tag and returns resulting HTML
      @param String name name of the placeholder
      @param String content html-contents of the placeholder
      @return String
      ###
      classParam = ""
      if @_placeholdersClasses[name]
        classParam = "class=\"#{ @_placeholdersClasses[name] }\""

      "<div id=\"#{ @_getPlaceholderDomId(name) }\"  #{ classParam }>#{ content }</div>"


    renderInlineTag: (name, content) ->
      ###
      Builds and returns correct html-code of the widget's inline root tag with the given name and rendered contents.
      @param String name inline name
      @param String content rendered template of the widget
      @return Future[String]
      ###
      info = @ctx[':inlines'][name]
      @getStructTemplate().then (struct) =>
        classString =
          # widget's classes should be injected to it's inlines only if the widget doesn't have it's own DOM root
          # (i.e. extended widgets)
          if struct.isExtended()
            @_buildClassString(info.class)
          else
            info.class
        classAttr = if classString.length then ' class="' + classString + '"' else ''
        "<#{ info.tag } id=\"#{ info.id }\"#{ classAttr }>#{ content }</#{ info.tag }>"


    replaceModifierClass: (cls) ->
      ###
      Sets the new modifier class(es) (replacing the old if threre was) and immediately updates widget's root element
       with new "class" attribute in DOM.
      @param String cls space-separeted list of new modifier classes
      @browser-only
      ###
      @setModifierClass(cls)
      require ['jquery'], ($) =>
        $('#'+@ctx.id).attr('class', @_buildClassString())


    _buildClassString: (dynamicClass) ->
      classList = []
      classList.push(@cssClass) if @cssClass
      classList.push(@ctx._modifierClass) if @ctx._modifierClass
      classList.push(dynamicClass) if dynamicClass
      classList = classList.concat(@ctx.__cord_dyn_classes__) if @ctx.__cord_dyn_classes__?
      classList.join(' ')


    setModifierClass: (cls) ->
      ###
      Save modifier classes came from the template in the state of the widget.
      Need it to be able to restore when widget is re-rendered and the root tag is recreated.
      @param String class space-separeted list of css class-names
      ###
      @ctx._modifierClass = cls


    addDynClass: (cls) ->
      ###
      Adds the specified CSS class for the root element(s) of the widget.
      This class is considered dynamically dependent from the current state of the widget.
      The list of such classes is preserved separately from the static `cssClass` field in a special context value and
       can be modified runtime via (add|remove|toggle)Class() methods of the widget's behaviour class.
      This method should be used only before first widget render (typically in the onShow() method). All later
       modifications should be done only in behaviour.
      @param {String} cls Single CSS class name to be added
      ###
      if cls
        @ctx.__cord_dyn_classes__ ?= []
        @ctx.__cord_dyn_classes__.push(cls) if @ctx.__cord_dyn_classes__.indexOf(cls) == -1


    addDataAttr: (key, value) ->
      ###
      Adds the specified data property for the root element(s) of the widget.
      @param {String} key Single key to be added
      @param {String} value Single value to be added
      ###
      if key and value
        @ctx.__cord_data_attrs__ ?= {}
        @ctx.__cord_data_attrs__[key] = value


    _saveContextVersionForBehaviourSubscriptions: ->
      if not @_behaviourContextBorderVersion?
        @_behaviourContextBorderVersion = @ctx.getVersion()
        @ctx.stashEvents()


    setSubscribedPushBinding: (pushBindings) ->
      ###
      Set widget's push bindings of parent widget context
      @param Object push binding by parent context param's name
      ###
      @_subscibedPushBindings = pushBindings


    _renderPlaceholder: (name, domInfo) ->
      ###
      Render contents of the placeholder with the given name
      @param String name name of the placeholder to render
      @param Function(String, Array) callback result-callback with resulting HTML and special helper structure with
                                     information about contents (needed by replacePlaceholders() method)
      ###
      placeholderOut = []
      renderInfo = []
      promise = new Future("#{ @debug('_renderPlaceholder') }")

      self = this
      i = 0
      placeholderOrder = {}
      phs = @ctx[':placeholders'] ? []
      ph = phs[name] ? []

      for info in ph
        do (info) =>
          promise.fork()

          widgetId = info.widget
          widget = @widgetRepo.getById(widgetId)
          widget.setModifierClass(info.class) if info.type != 'inline'

          timeoutTemplateOwner = info.timeoutTemplateOwner
          delete info.timeoutTemplateOwner

          processWidget = (out) ->
            ###
            DRY for regular widget result fixing
            ###
            placeholderOut[placeholderOrder[widgetId]] = widget.renderRootTag(out)
            renderInfo.push(type: 'widget', widget: widget)
            renderInfo.push(subInfo) for subInfo in widget.getPlaceholdersRenderInfo()
            # TODO: may be we can clean placeholders render info here to free some memory

          processTimeoutStub = ->
            widget._delayedRender = true
            TimeoutStubHelper.getTimeoutHtml(timeoutTemplateOwner, info.timeoutTemplate, widget).then (out) ->
              placeholderOut[placeholderOrder[widgetId]] = widget.renderRootTag(out)
              renderInfo.push(type: 'timeout-stub', widget: widget)
              promise.resolve()
              return
            .catch (err) -> promise.reject(err)

          replaceTimeoutStub = (out, timeoutDomInfo) ->
            ###
            DRY insert actual content of the widget instead of timeout stub, inserted before
            @browser-only
            ###
            if not promise.completed()
              widget._delayedRender = false
              processWidget(out)
            else
              TimeoutStubHelper.replaceStub(out, widget, domInfo).then ($newRoot) ->
                timeoutDomInfo.setDomRoot($newRoot)
                domInfo.domInserted().done -> timeoutDomInfo.markShown()
              .catchIf (err) ->
                err instanceof errors.WidgetDropped


          if info.type == 'widget'
            placeholderOrder[widgetId] = i

            complete = false
            timeoutDomInfo = domInfo
            hasTimeout = isBrowser and info.timeout? and info.timeout >= 0

            if hasTimeout
              # Creating "internal" DOM root info for the widget with timeout to be able to organize
              #  the order and right context for replacement of serveral timeouted blocks enclosed into each other
              timeoutDomInfo = new DomInfo(@debug('_renderPlaceholder:widget:timeout'))
              setTimeout ->
                # if the widget has not been rendered within given timeout, render stub template from the {:timeout} block
                if not complete
                  complete = true
                  processTimeoutStub().failAloud(self.debug("_renderPlaceholder:processTimeoutStub:#{widget.debug()}"))
              , info.timeout

            widget.show(info.params, timeoutDomInfo).then (out) ->
              if not complete
                # in case of no timeout just linking to the upper DOM info
                timeoutDomInfo.completeWith(domInfo) if hasTimeout
                processWidget(out)
                promise.resolve()
                complete = true # should be here to avoid returning `promise` (above) and locking to it
              else
                replaceTimeoutStub(out, timeoutDomInfo)
            .catch (err) -> promise.reject(err)

          else if info.type == 'timeouted-widget'
            placeholderOrder[widgetId] = i
            timeoutDomInfo = new DomInfo(@debug('_renderPlaceholder:timeouted-widget:timeout'))
            info.timeoutPromise.then (params) ->
              widget.show(params, timeoutDomInfo)
            .zip(processTimeoutStub()).then (out) ->
              replaceTimeoutStub(out, timeoutDomInfo)
            # not catching here because the promise should be fulfilled in processTimeoutStub()
            .failAloud(@debug("_renderPlaceholder:timeouted-widget:#{widget.debug()}"))

          else if info.type == 'inline'
            placeholderOrder[info.template] = i

            inlineId = "inline-#{ widget.ctx.id }-#{ info.name }"
            widget.ctx[':inlines'] ?= {}
            widget.ctx[':inlines'][info.name] =
              id: inlineId
              template: info.template
              class: info.class
              tag: info.tag
            widget.renderInline(info.name, domInfo).then (out) ->
              widget.renderInlineTag(info.name, out)
            .then (wrappedOut) =>
              placeholderOut[placeholderOrder[info.template]] = wrappedOut
              renderInfo.push(type: 'inline', name: info.name, widget: widget)
              promise.resolve()
              return
            .catch (err) -> promise.reject(err)

          else # if info.type == 'placeholder'
            orderId = 'placeholder-' + info.name
            placeholderOrder[orderId] = i
            widget._renderPlaceholder(info.name, domInfo).then (out) ->
              widget._placeholdersClasses[info.name] = info.class if info.class
              placeholderOut[placeholderOrder[orderId]] = widget.renderPlaceholderTag(info.name, out)
              promise.resolve()
              return
            .catch (err) -> promise.reject(err)

          i++

      promise.then =>
        @_placeholdersRenderInfo.push(info) for info in renderInfo # collecting render info for the future usage by the enclosing widget
        [placeholderOut.join(''), renderInfo]


    getPlaceholdersRenderInfo: ->
      @_placeholdersRenderInfo


    _getPlaceholderDomId: (name) ->
      'ph-' + @ctx.id + '-' + name


    definePlaceholders: (placeholders) ->
      @ctx[':placeholders'] = placeholders


    addInlineDomRoot: (domRoot) ->
      ###
      Helper method to aggregate inlines' root elements of this widget to be able to pass them to the browserInit later
      @param jQuery domRoot the new root element of the inline to add
      ###
      @_inlinesRuntimeInfo.push(domRoot)


    replacePlaceholders: (placeholders, structTmpl, replaceHints, transition) ->
      ###
      Replaces contents of the placeholders of this widget according to the given params
      @browser-only
      @param Object placeholders meta-information about new placeholders contents
      @param StructureTemplate structTmpl structure template of the calling widget
      @param Object replaceHints pre-calculated helping information about which placeholders should be replaced
                                 and which should not
      @return Future
      ###
      Future.require('cord!utils/DomHelper', 'jquery').then (DomHelper, $) =>
        readyPromise = new Future(@debug('replacePlaceholders:readyPromise'))

        ph = {}
        @ctx[':placeholders'] ?= []
        for name, items of placeholders
          ph[name] = []
          for item in items
            ph[name].push item
          # remove replaced placeholder is needed to know what remaining placeholders need to cleanup
          if @ctx[':placeholders'][name]?
            delete @ctx[':placeholders'][name]

        # cleanup empty placeholders
        for name of @ctx[':placeholders']
          $('#' + @_getPlaceholderDomId name).empty()

        @ctx[':placeholders'] = ph
        @_placeholdersRenderInfo = []

        for name, items of ph
          do (name) =>
            if replaceHints[name].replace
              domInfo = new DomInfo("#{ @debug('renderPlaceholders') } -> #{name}")
              @_renderPlaceholder(name, domInfo).then (out, renderInfo) =>
                $el = $(@renderPlaceholderTag(name, out))
                domInfo.setDomRoot($el)
                aggregatePromise = new Future(@debug('replacePlaceholders:aggregatePromise')) # full placeholders members initialization promise
                for info in renderInfo
                  switch info.type
                    when 'inline' then info.widget.addInlineDomRoot($el)
                    when 'widget' then aggregatePromise.when(info.widget.browserInit($el))
                    #when 'timeout-stub' then aggregatePromise.when(info.widget.timeoutReady())
                aggregatePromise.then =>
                  # Inserting placeholder contents to the DOM-tree only after full behaviour initialization of all
                  # included widgets but not inline-blocks. Timeout-stubs are not waited for yet as they have no
                  # any behaviour initialization support yet.
                  if not @_sentenced
                    DomHelper.replace($('#'+@_getPlaceholderDomId(name)), $el)
                  else
                    throw new errors.WidgetSentenced(
                      "Couldn't replace placeholder #{name} because widget #{@constructor.__name} is sentenced!"
                    )
                .then ->
                  info.widget.markShown() for info in renderInfo when info.type is 'widget'
                  domInfo.markShown()
              .link(readyPromise)
            else
              i = 0
              for item in items
                do (item, i) =>
                  widget = @widgetRepo.getById item.widget
                  widget.replaceModifierClass(item.class)
                  structTmpl.replacePlaceholders(
                    replaceHints[name].items[i],
                    widget.ctx[':placeholders'],
                    transition
                  ).then ->
                    widget.setParamsSafe(item.params)
                  .link(readyPromise)
                i++

        readyPromise


    getInitCode: (parentId) ->
      parentStr = if parentId? then ",'#{ parentId }'" else ''

      namedChilds = {}
      for name, widget of @childByName
        namedChilds[widget.ctx.id] = name

      serializedModelBindings = {}
      for key, mb of @_modelBindings
        serializedModelBindings[key] = mb.model.serializeLink()

      # filter bad unicode characters before sending data to browser
      ctxString = unescape(encodeURIComponent(JSON.stringify(@ctx))).replace(/[\\']/g, '\\$&')

      jsonParams = [namedChilds, @childBindings, serializedModelBindings]
      jsonParamsString = (jsonParams.map (x) -> JSON.stringify(x)).join(',')

      """
      wi.init('#{ @getPath() }','#{ ctxString }',#{ jsonParamsString },#{ @_isExtended }#{ parentStr });
      #{ (widget.getInitCode(@ctx.id) for widget in @children).join '' }
      """


    getDeepCssList: ->
      ###
      Returns list of css-files required by this widget and all it's children
      @return Array[String]
      ###
      result = []
      @collectDeepCssListRec(result)
      _.unique(result)


    collectDeepCssListRec: (result) ->
      ###
      Recursively scans tree of widgets and collects list of required css-files.
      @param Array[String] result accumulating result array
      ###
      result.push(css) for css in @getCssFiles()
      child.collectDeepCssListRec(result) for child in @children


    getCssFiles: ->
      ###
      Returns list of full paths to css-files of this widget
      @return Array[String]
      ###
      result = []
      if @css?
        if _.isArray @css
          result.push cssHelper.expandPath(css, this) for css in @css
        else if @css
          result.push cssHelper.expandPath(@constructor.dirName, this)
      result


    debug: (method) ->
      ###
      Return identification string of the current widget for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @getPath() }(#{ @ctx.id })#{ methodStr }"


    resetChildren: ->
      ###
      Cleanup all internal state about child widgets.
      This method is called when performing full re-rendering of the widget.
      ###
      @children = []
      @childByName = {}
      @childById = {}
      @childBindings = {}


    _resetWidgetReady: ->
      ###
      Resets widget's browser-side initialization state to be able to correctly run browserInit()
      ###
      if isBrowser
        @_widgetReadyPromise = Future.single(@debug('_widgetReadyPromise'))
        @_browserInitialized = false
        @_shownPromise.clear() if @_shownPromise?
        @_shownPromise = Future.single('Widget::_shownPromise ' + @constructor.__name)
        @_shown = false


    drop: ->
      ###
      Removes self from widget repo
      ###
      @widgetRepo.dropWidget @ctx.id


    registerChild: (child, name) ->
      ###
      Registers given `child` widget in the internal structures of this widget
      @param {Widget} child The child widget to be registered
      @param (optional){String} name If given the child widget will be added to the `childByName` map
      ###
      @widgetRepo.detachWidget(child, this)
      if not @_sentenced
        # debugging impossible
        if child == this
          _console.error "ERROR: Self child binding detected for #{@debug()}! This should be impossible! Ignoring..."
          return

        # check if this is duplicate call
        if not @childById[child.ctx.id]
          @children.push(child)
          @childById[child.ctx.id] = child
          @widgetRepo.registerParent child, this
          @_bindChildEvents(child, name)

        # may be the child was firstly registered without name and then re-resitered with name
        @childByName[name] = child if name?
        return
      else
        throw new errors.WidgetSentenced(
          "Couldn't register child #{child.constructor.__name} because parent #{@constructor.__name} is sentenced!"
        )


    unbindChild: (child) ->
      ###
      Removes the given widget from the list of children on the current widget
      @param Widget child child widget object
      ###
      index = @children.indexOf(child)
      if index != -1
        @children.splice index, 1
        delete @childById[child.ctx.id]
        delete @childBindings[child.ctx.id]

        childName = null
        for name, widget of @childByName
          if widget == child
            childName = name
            delete @childByName[name]
            break

        @_unbindChildEvents(child, childName)
        child.cleanSubscriptions()

        @widgetRepo.unregisterParent(child)
      else
        throw new Error("Trying to remove unexistent child of widget #{ @constructor.__name }(#{ @ctx.id }), " +
                        "child: #{ child.constructor.__name }(#{ child.ctx.id })")


    dropChild: (childId) ->
      ###
      Drops and unregisters the child widget with the given id
      @param String childId
      ###
      childWidget = @childById[childId]
      @unbindChild(childWidget)
      childWidget.drop()


    _bindChildEvents: (childWidget, childName) ->
      ###
      Subscribes to the child widget's events according to the @childEvents definition of the widget class.
      This method is called every time new child widget is attached to this widget.
      Special widget name ":any" is supported and means any child widget with or without any name.
      @param {Widget} childWidget The child widget to subscribe to
      @param {String} childName Optional name of the child widget to select proper callbacks from the subscription map
      ###
      subs = @constructor._childEventSubscriptions
      if childName and subs[childName]
        for topic, callbacks of subs[childName]
          childWidget.on(topic, cb).withContext(this) for cb in callbacks
      if subs[':any']
        for topic, callbacks of subs[':any']
          childWidget.on(topic, cb).withContext(this) for cb in callbacks


    _unbindChildEvents: (childWidget, childName) ->
      ###
      Unsubscribes from the given child widget's events
      @param {Widget} childWidget The child widget to subscribe to
      @param {String} childName Optional name of the child widget to select proper callbacks from the subscription map
      ###
      subs = @constructor._childEventSubscriptions
      if childName and subs[childName]
        for topic of subs[childName]
          childWidget.off(topic, this)
      if subs[':any']
        for topic of subs[':any']
          childWidget.off(topic, this)


    getBehaviourClass: ->
      @behaviourClass = "#{ @constructor.__name }Behaviour" if not @behaviourClass?
      if @behaviourClass == false
        null
      else
        @behaviourClass


    initBehaviour: ($domRoot) ->
      ###
      Correctly (re)creates the behaviour instance for the widget if there is defined behaviour
      @browser-only
      @param jQuery $domRoot injected DOM root for the widget
      ###
      @_cleanBehaviour()

      behaviourClass = @getBehaviourClass()

      if behaviourClass
        Future.require("cord!/#{ @getDir() }/#{ behaviourClass }", 'cord!Behaviour').then (BehaviourClass, Behaviour) =>
          if not @_sentenced
            # TODO: move this check to the build phase
            if BehaviourClass.prototype instanceof Behaviour
              @behaviour = new BehaviourClass(this, $domRoot)
              @container.injectServices(@behaviour).then =>
                @behaviour.init()
                return
            else
              throw new Error("WRONG BEHAVIOUR CLASS: #{behaviourClass}")
        .catch (err) =>
          _console.error "#{ @debug 'initBehaviour' } --> error occurred while loading behaviour:", err
          postal.publish 'error.notify.publish',
            link: ''
            message: "Ошибка загрузки виджета #{ behaviourClass }. Попробуйте перезагрузить страницу."
            details: String(err)
            error: true
            timeOut: 30000
          throw err
      else
        Future.resolved()


    createChildWidget: (type, name) ->
      ###
      Dynamically creates new child widget with the given canonical type
      @param String type new widget type (absolute or in context of the current widget)
      @param (optional)String name optional name for the new widget
      @return Future[Widget] new child widget
      ###
      @widgetRepo.createWidget(type, this, name, @getBundle())


    injectChildWidget: (type, params = {}) ->
      ###
      Dynamically creates and injects a new widget as a child of this widget on browser-side.
      Behaviour is required.
      This method is mainly necessary for injecting debug tools and other "plugins".
      @browserOnly
      @param {String} type widget type in canonical format (absolute or in context of the current widget)
      @param (optional){Object} params new widget's params and special positioning params
                                       (see Behaviour::insertChildWidget)
      @return Future[Array[jQuery, Widget]]
      ###
      if @behaviour
        @behaviour.insertChildWidget(type, params)
      else
        Future.rejected(new Error("Injecting child widget into behaviourless widget [#{@debug()}] is not supported!"))


    browserInit: (stopPropagateWidget, $domRoot) ->
      ###
      Almost copy of widgetRepo::init but for client-side rendering
      @browser-only
      @param (optional)Widget stopPropageteWidget widget for which method should stop pass browserInit to child widgets
      @param (optional)jQuery domRoot injected DOM root for the widget or it's children
      @return Future()
      ###
      _console.log "#{ @debug 'browserInit' }" if global.config.debug.widget

      if not @_browserInitialized and not @_delayedRender and not @_sentenced
        @_browserInitialized = true

        if stopPropagateWidget? and not (stopPropagateWidget instanceof Widget)
          $domRoot = stopPropagateWidget
          stopPropagateWidget = undefined

        if this != stopPropagateWidget and not @_delayedRender
          for widgetId, bindingMap of @childBindings
            @childById[widgetId].setSubscribedPushBinding(bindingMap)

          readyConditions = []

          for childWidget in @children
            # we should not wait for readiness of the child widget if it is going to render later (with timeout-stub)
            if not childWidget._delayedRender
              readyConditions.push(childWidget.browserInit(stopPropagateWidget, $domRoot))

          childWidgetsReadyPromise = Future.sequence(readyConditions)

          readyConditions.push(@constructor._cssPromise)

          selfInitBehaviour = false
          readyConditions.push @initBehaviour($domRoot).done =>
            @ctx.replayStashedEvents()
            selfInitBehaviour = true

          @_widgetReadyPromise.when(Future.sequence(readyConditions)).done =>
            if @_browserInitDebugTimeout
              clearTimeout(@_browserInitDebugTimeout)
              @_browserInitDebugTimeout = null
            @emit 'render.complete'

          # This code is for debugging puroses: it clarifies if there are some bad situations
          # when widget doesn't become ready at all even after 5 seconds. Likely that points to some errors in logic.
          savedPromiseForTimeoutCheck = @_widgetReadyPromise
          savedConstructorCssPromise = @constructor._cssPromise
          @_browserInitDebugTimeout = setTimeout =>
            if not childWidgetsReadyPromise.completed()
              errorInfo =
                futureCounter: childWidgetsReadyPromise._counter
                childCount: @children.length
                isSentenced: @isSentenced()
                stuckChildInfo: []
              i = 0
              for childWidget in @children
                if not childWidget.ready().completed()
                  errorInfo.stuckChildInfo.push
                    index: i
                    widget: childWidget.debug()
                    isSentenced: childWidget.isSentenced()
                    browserInitialized: childWidget._browserInitialized
                    delayedRender: childWidget._delayedRender
                    behaviourPresent: childWidget.behaviour?
                    futureCounter: childWidget.ready()._counter
                else
                  errorInfo.stuckChildInfo.push childWidget.ready().completed()
                i++
              _console.warn "#{ @debug 'incompleteBrowserInit:children!' }", errorInfo
            else if not savedPromiseForTimeoutCheck.completed()
              _console.warn "#{ @debug 'incompleteBrowserInit!' } css:#{ savedConstructorCssPromise.completed() } child:#{ childWidgetsReadyPromise.completed() } selfInit:#{ selfInitBehaviour }"
            @_browserInitDebugTimeout = null
          , 5000
      @_widgetReadyPromise


    subscribeChildPushBindings: (widget, bindingMap) ->
      ###
      Subscribe the given child widget to the current widget's context changes
      @param Widget widget the child widget
      @param Object bindingMap { widget_param_name: current_widget_context_param }
      ###
      for paramName, ctxName of bindingMap
        @widgetRepo.subscribePushBinding @ctx.id, ctxName, widget, paramName


    ready: ->
      ###
      Returns the widget's 'ready' promise.
      @return Future
      ###
      @_widgetReadyPromise


    shown: ->
      ###
      Returns the widget's 'show' promise
      @return Future
      ###
      @_shownPromise


    markShown: (ignoreChildren = false) ->
      ###
      Triggers widget's show events and promises.
      This method should be called when the widget's body is actually shown in the DOM.
      @param Boolean ignoreChildren if true doesn't recursively call markShown for it's child widgets
      ###
      if not @_shown and not @_delayedRender # timeouted widget should not be marked as shown
        child.markShown() for child in @children if not ignoreChildren
        # _shown is necessary to protect from duplicate recursive calling of markShown() from the future's callbacks
        # this redundancy can be removed when inline-generated widgets will have appropriate detection and separation API
        @_shown = true
        @_shownPromise?.resolve()
        @emit 'show'


    markRenderStarted: ->
      @_renderInProgress = true


    markRenderFinished: ->
      @_renderInProgress = false
      if @_childWidgetCounter == 0
        postal.publish "widget.#{ @ctx.id }.render.children.complete", {}


    childWidgetAdd: ->
      @_childWidgetCounter++


    childWidgetComplete: ->
      @_childWidgetCounter--
      if @_childWidgetCounter == 0 and not @_renderInProgress
        postal.publish "widget.#{ @ctx.id }.render.children.complete", {}


    subscribeValueChange: (params, name, value, callback) ->
      subscription = postal.subscribe
        topic: "widget.#{ @ctx.id }.change.#{ value }"
        callback: (data) ->
          if data.value != ':deferred'
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
            subscription.unsubscribe()

      #Assure subscription cleaning in case of early object destruction before everything happens
      @addTmpSubscription subscription


    getBaseContext: ->
      @_baseContext ? (@_baseContext = @_buildBaseContext())


    _buildBaseContext: ->
      dust.makeBase

        widget: (chunk, context, bodies, params) =>
          ###
          {#widget/} block handling
          ###
          @childWidgetAdd()

          if params.type.substr(0, 2) == './'
            params.type = "//#{@constructor.relativeDir}#{params.type.substr(1)}"

          chunk.map (chunk) =>
            normalizedName = if params.name then params.name.trim() else undefined
            normalizedName = undefined if not normalizedName

            timeout = if params.timeout? then parseInt(params.timeout) else -1
            hasTimeout = isBrowser and timeout >= 0
            timeoutDomInfo = if hasTimeout then new DomInfo(@debug('#widget::timeout')) else @_domInfo

            @getStructTemplate().then (tmpl) =>
              # creating widget from the structured template or not depending on it's existence and name
              # btw getting and pushing futher timeout template name from the structure template if there is one
              if tmpl.isEmpty() or not normalizedName
                @widgetRepo.createWidget(params.type, this, normalizedName, @getBundle())
              else if normalizedName
                tmpl.getWidgetByName(normalizedName).then (widget) ->
                  [widget, tmpl.getWidgetInfoByName(normalizedName).timeoutTemplate]
                .catch =>
                  @widgetRepo.createWidget(params.type, this, normalizedName, @getBundle())
              # else impossible

            .then (widget, timeoutTemplate) =>
              complete = false

              @resolveParamRefs(widget, params).then (resolvedParams) =>
                widget.setModifierClass(params.class)
                widget.show(resolvedParams, timeoutDomInfo)
              .then (out) =>
                if not complete
                  complete = true
                  timeoutDomInfo.completeWith(@_domInfo) if hasTimeout
                  @childWidgetComplete()
                  chunk.end(widget.renderRootTag(out))
                else
                  TimeoutStubHelper.replaceStub(out, widget, @_domInfo).then ($newRoot) =>
                    timeoutDomInfo.setDomRoot($newRoot)
                    @_domInfo.domInserted().done -> timeoutDomInfo.markShown()
                  .catchIf (err) ->
                    err instanceof errors.WidgetDropped or err instanceof errors.WidgetSentenced
              .catch (err) ->
                _console.error("Error on widget #{ widget.debug() } rendering:", err)
                chunk.setError(err)

              if hasTimeout
                setTimeout =>
                  # if the widget has not been rendered within given timeout, render stub template from the {:timeout} block
                  if not complete
                    complete = true
                    widget._delayedRender = true
                    TimeoutStubHelper.getTimeoutHtml(this, timeoutTemplate, widget).then (out) =>
                      @childWidgetComplete()
                      chunk.end(widget.renderRootTag(out))
                    .catch (err) ->
                      chunk.setError(err)
                , timeout
            .catch (err) ->
              chunk.setError(err)


        deferred: (chunk, context, bodies, params) =>
          ###
          {#deferred/} block handling
          ###
          if bodies.block?
            deferredId = @_deferredBlockCounter++
            deferredKeys = params.params.split /[, ]/
            needToWait = (name for name in deferredKeys when @ctx.isDeferred(name))

            promise = new Future(@debug('deferred'))
            for name in needToWait
              do (name) =>
                promise.fork()
                subscription = postal.subscribe
                  topic: "widget.#{ @ctx.id }.change.#{ name }"
                  callback: (data) ->
                    if data.value != ':deferred'
                      promise.resolve()
                      subscription.unsubscribe()
                @addTmpSubscription subscription

            @childWidgetAdd()
            chunk.map (chunk) =>
              promise.then =>
                TimeoutStubHelper.renderTemplateFile(this, "__deferred_#{deferredId}")
              .then (out) =>
                @childWidgetComplete()
                chunk.end(out)
              .failAloud(@debug('#deferred'))
          else
            ''


        placeholder: (chunk, context, bodies, params) =>
          ###
          {#placeholder/} block handling
          Placeholder - point of extension of the widget.
          ###
          @childWidgetAdd()
          chunk.map (chunk) =>
            name = params?.name ? 'default'
            if params and params.class
              @_placeholdersClasses[name] = params.class

            @_renderPlaceholder(name, @_domInfo).then (out) =>
              @childWidgetComplete()
              chunk.end(@renderPlaceholderTag(name, out))
            .catch (err) ->
              chunk.setError(err)


        i18n: (chunk, context, bodies, params) =>
          ###
          {#i18n text="" [context=""] [wrapped="true"] /}
          ###
          text = params.text or ''
          delete(params.text)

          if @ctx.i18nHelper
            chunk.write(@ctx.i18nHelper(text, params))
          else
            chunk.write(text)


        url: (chunk, context, bodies, params) =>
          ###
          {#url routeId="" [param1=""...] /}
          ###
          routeId = params.routeId
          if not routeId
            throw new Error @debug("RouteId is require for #url")

          delete(params.routeId)

          @widgetRepo.getServiceContainer().eval 'router', (router) ->
            chunk.write(router.urlTo(routeId, params))


        #
        # Widget initialization script generator
        #
        widgetInitializer: (chunk) =>
          if @widgetRepo._initEnd
            ''
          else
            chunk.map (chunk) =>
              subscription = postal.subscribe
                topic: "widget.#{ @ctx.id }.render.children.complete"
                callback: =>
                  chunk.end @widgetRepo.getTemplateCode()
                  subscription.unsubscribe()
              @addSubscription subscription


        # css include
        css: (chunk) =>
          chunk.map (chunk) =>
            subscription = postal.subscribe
              topic: "widget.#{ @ctx.id }.render.children.complete"
              callback: =>
                @widgetRepo.getTemplateCss().done (html) ->
                  chunk.end(html)
                subscription.unsubscribe()
            @addTmpSubscription subscription

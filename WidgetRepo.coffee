define [
  'cord!Collection'
  'cord!Context'
  'cord!css/helper'
  'cord!deferAggregator'
  'cord!errors'
  'cord!isBrowser'
  'cord!Model'
  'cord!ModelRepo'
  'cord!utils/Future'
  'postal'
  'underscore'
  'cord!AppConfigLoader'
  'cord!Utils'
], (Collection, Context, cssHelper, deferAggregator, errors, isBrowser, Model, ModelRepo, Future, postal, _, AppConfigLoader, Utils) ->

  class WidgetRepo

    widgets: null
    rootWidget: null

    serviceContainer: null
    request: null
    response: null

    # auxiliary variables for widget initialization support on page loading at browser side
    _initPromise: null
    _parentPromises: null
    _widgetOrder: null
    _pushBindings: null

    # list of widgets which build main hierarchy of widget's via #extend template calls
    # begins from the most specific widget (leaf) and ends with most common (root) which doesn't extend another widget
    _currentExtendList: null


    constructor: (@serverProfilerUid = '') ->
      @widgets = {}
      @_widgetOrder = []
      @_pushBindings = {}
      @_currentExtendList = []
      if isBrowser
        @_initPromise = new Future('WidgetRepo::_initPromise')
        @_parentPromises = {}


    setServiceContainer: (serviceContainer) ->
      @serviceContainer = serviceContainer


    getServiceContainer: ->
      @serviceContainer


    setRequest: (request) ->
      @request = request


    getRequest: ->
      @request


    setResponse: (response) ->
      @response = response


    getResponse: ->
      @response


    createWidget: (path, parentWidget, name, contextBundle) ->
      ###
      Main widget factory.
      All widgets should be created through this call.
      @param {String} path canonical path of the widget
      @param (optional){Widget} parentWidget parent widget in which the new widget should be registered as child
      @param (optional){String} name name of the created widget in the parent's widget namespace (childByName)
      @param (optional)String contextBundle calling context bundle to expand relative widget paths
      @return {Future[Widget]}
      ###
      bundleSpec = if contextBundle then "@#{ contextBundle }" else ''

      Future.require("cord-w!#{ path }#{ bundleSpec }").then (WidgetClass) =>
        widget = new WidgetClass
          repo: this
          serviceContainer: @serviceContainer

        if widget.getPath() == '/cord/core//Switcher' and contextBundle?
          widget._contextBundle = contextBundle

        @widgets[widget.ctx.id] =
          widget: widget

        Future.try =>
          parentWidget.registerChild(widget, name) if parentWidget

          injectRouterPromise = @serviceContainer.getService('router').then (router) ->
            widget.router = router
          .catch (err) -> # compatibility with compiling index.html when services are not defined
            null
          Future.sequence [
            @serviceContainer.injectServices(widget)
            injectRouterPromise
          ]
          .then -> widget
        .catch (err) =>
          @dropWidget(widget.ctx.id)
          throw err


    dropWidget: (id) ->
      if info = @widgets[id]
        info.parent.unbindChild(info.widget) if info.parent
        info.widget.clean()
        info.widget = null
        delete @widgets[id]
      else
        _console.warn "Trying to drop unknown widget with id = #{ id }"


    registerParent: (childWidget, parentWidget) ->
      ###
      Register child-parent relationship in the repo
      ###
      info = @widgets[childWidget.ctx.id]
      if info?
        info.parent.unbindChild(childWidget) if info.parent? and info.parent != parentWidget
        info.parent = parentWidget
      return


    unregisterParent: (childWidget) ->
      @widgets[childWidget.ctx.id].parent = null


    detachWidget: (childWidget, exceptParentWidget) ->
      ###
      Detaches the given childWidget from it's parent (if there is) except if the parent is the given one.
      ###
      info = @widgets[childWidget.ctx.id]
      if info and info.parent and info.parent != exceptParentWidget
        info.parent.unbindChild(childWidget)
      return


    setRootWidget: (widget) ->
      info = @widgets[widget.ctx.id]
      if info.parent?
        info.parent.unbindChild widget
      info.parent = null
      @rootWidget = widget


    getRootWidget: ->
      @rootWidget


    gcWidgets: ->
      ###
      Collects all registered widgets that are not the current root widget's children and drop them after some timeout.
      WARNING: this method of GC can be buggy and causing serious problems with the stability of application.
       Should be disabled if dropping of unexpected widgets start to appear.
      @return {Boolean} true if any widgets has been scheduled to be dropped
      ###
      return false if @_gcTimeout # schedule only one GC task at a time
      root = @rootWidget
      okWidgetIds = []
      recCollectIds = (widget) =>
        okWidgetIds.push(widget.ctx.id)
        recCollectIds(child) for child in widget.children

      recCollectIds(root)

      gcIds = _.difference(Object.keys(@widgets), okWidgetIds)

      if gcIds.length
        @_gcTimeout = setTimeout =>
          _console.warn "GC widgets for widget", root, gcIds.map (id) =>
            if @widgets[id]
              # debugging very bad situation when wrong widget is going to be dropped
              if @widgets[id].widget.constructor.__name in ['Main', 'Base']
                _console.error "<<<<<< Going to kill Main! >>>>>"
                _console.log 'extend list', @_currentExtendList
                _console.log 'root children', root.children
              @widgets[id].widget.debug()
          @dropWidget(id) for id in gcIds when @widgets[id]
          @_gcTimeout = null
        , 120000
      return gcIds.length > 0


    _unserializeModelBindings: (serializedBindings) ->
      ###
      Simply replaces serialized links to models and collections to the actual restored instances of those
       models and collections in the given map.
      @param Object serializedBindings
      @param Function(Object) callback "result" callback with the converted map
      ###
      promise = new Future('WidgetRepo::_unserializeModelBindings')
      result = {}
      for key, value of serializedBindings
        do (key) =>
          if Collection.isSerializedLink(value)
            promise.fork()
            Collection.unserializeLink value, @serviceContainer, (collection) ->
              result[key] = model: collection
              promise.resolve()
          else if Model.isSerializedLink(value)
            promise.fork()
            Model.unserializeLink value, @serviceContainer, (model) ->
              result[key] = model: model
              promise.resolve()

      promise.then -> result


    initRepo: (repoServiceName, collections, promise) ->
      ###
      Helper method used in generated initialization code to restore models came from server in the browser
      @browser-only
      @param String repoServiceName name of the model repository service name
      @param Object collections list of serialized registered collections keyed with their names
      @param Future promise a promise that must be resolved when collections are initialized
      ###
      collections = JSON.parse(decodeURIComponent(escape(collections))) # decode utf-8 and parse

      @serviceContainer.eval repoServiceName, (repo) ->
        repo.setCollections(collections).done -> promise.resolve()


    getModelsInitCode: ->
      ###
      Generates code for passing and initializing of all model repositories from server-side into browser.
      Loops through service container to find all repository services.
      ###
      result = []
      for key, val of @serviceContainer.allInstances()
        if val instanceof ModelRepo
          escapedString = unescape(encodeURIComponent(JSON.stringify(val))).replace(/[\\']/g, '\\$&')
          result.push("wi.initRepo('#{ key }', '#{ escapedString }', p.fork());")
      result.join("\n")


    getTemplateCode: ->
      baseUrl = if global.config.localFsMode then '' else '/'
      config = if global.config.localFsMode then global.appConfig else @serviceContainer.get('appConfig')

      initUrl = if global.config.browserInitScriptId
        "#{baseUrl}assets/z/#{global.config.browserInitScriptId}.js"
      else
        "#{baseUrl}bundles/cord/core/init/browser-init.js?release=" + global.config.static.release

      """
      #{ if global.config.injectCordova then "<script src=\"#{baseUrl}cordova.js\"></script>" else '' }
      <script>
        var global = {
          cordServerProfilerUid: "#{ @serverProfilerUid }",
          config: #{ JSON.stringify(config.browser) }
        };
      </script>
      <script data-main="#{initUrl}" src="#{baseUrl}vendor/requirejs/require.js?release=#{global.config.static.release}"></script>
      <script>
          function cordcorewidgetinitializerbrowser(wi) {
            requirejs(['cord!utils/Future'], function(Future) {
              p = new Future('WidgetRepo::templateCode');
              #{ @getModelsInitCode() }
              wi.getServiceContainer().eval('modelProxy', function(modelProxy) {
                p.done(function() {
                  modelProxy.restoreLinks().done(function() {
                    #{ @rootWidget.getInitCode() }
                    wi.endInit();
                  });
                });
              });
            });
          };
      </script>
      """


    getTemplateCss: ->
      Future.try =>
        cssHelper.getInitCssCode(@rootWidget.getDeepCssList())


    endInit: ->
      ###
      Performs final initialization of the transferred from the server-side objects on the browser-side.
      This method is called when all data from the server is loaded.
      @browser-only
      ###
      configPromise = Future.require('cord!AppConfigLoader').then (AppConfigLoader) ->
        AppConfigLoader.ready()
      Future.all([configPromise, @_initPromise]).spread (appConfig) =>
        # start services registered with autostart option
        @serviceContainer.autoStartServices(appConfig.services)
        # setup browser-side behaviour for all loaded widgets
        @_setupBindings().then =>
          # Remove 'm-not-ready' modifier. Elements are clickable now
          document.body.classList.remove('m-not-ready')
          # Initializing profiler panel
          if CORD_PROFILER_ENABLED
            if window.zone?
              tmpZone = window.zone
              window.zone = zone.constructor.rootZone
            topBaseWidget = @_currentExtendList[@_currentExtendList.length - 1]
            topBaseWidget.injectChildWidget '/cord/core//Profiler',
              ':context': $('body')
              ':position': 'append'
              serverUid: @serverProfilerUid
            .failAloud()
            if window.zone?
              window.zone = tmpZone

        # for GC
        @_parentPromises = null
        @_initPromise = null
        @_pushBindings = null


    init: (widgetPath, ctx, namedChilds, childBindings, modelBindings, isExtended, parentId) ->
      ###
      Restores widget's state after transferring from server to browser (initial html-page loading)
      @browser-only
      ###
      ctx = JSON.parse(decodeURIComponent(escape(ctx))) # decode utf-8 and parse

      @_widgetOrder.push(ctx.id)

      for widgetId, bindingMap of childBindings
        @_pushBindings[widgetId] = {}
        for ctxName, paramName of bindingMap
          @_pushBindings[widgetId][ctxName] = paramName

      @_parentPromises[ctx.id] = Future.single("WidgetRepo::parentPromise(#{widgetPath}, #{ctx.id})")

      Future.sequence([
        Future.require("cord-w!#{ widgetPath }")
        Context.fromJSON(ctx, @serviceContainer)
        @_unserializeModelBindings(modelBindings)
      ]).spread (WidgetClass, ctx, modelBindings) =>

        widget = new WidgetClass
          context: ctx
          repo: this
          serviceContainer: @serviceContainer
          modelBindings: modelBindings
          extended: isExtended
          restoreMode: true

        if @_pushBindings[ctx.id]?
          widget.setSubscribedPushBinding(@_pushBindings[ctx.id])
          for ctxName, paramName of @_pushBindings[ctx.id]
            @subscribePushBinding(parentId, ctxName, widget, paramName)

        @widgets[ctx.id] =
          widget: widget
          namedChilds: namedChilds

        @serviceContainer.injectServices(widget).link(@_parentPromises[ctx.id]).then =>
          if parentId?
            @_parentPromises[parentId].then =>
              @widgets[parentId].widget.registerChild(widget, @widgets[parentId].namedChilds[ctx.id] ? null)
              if widgetPath == '/cord/core//Switcher'
                widget._contextBundle = @widgets[parentId].widget.getBundle()
          else
            @rootWidget = widget

      .link(@_initPromise)
      .failAloud("WidgetRepo::init:#{widgetPath}:#{ctx.id}")


    _setupBindings: ->
      # organizing extendList in right order
      for id in @_widgetOrder
        widget = @widgets[id].widget
        if widget._isExtended
          @_currentExtendList.push(widget)
      # initializing DOM bindings of widgets in reverse order (leafs of widget tree - first)
      bindPromises = (@bind(id) for id in @_widgetOrder.reverse())
      result = Future.sequence(bindPromises)
      @serviceContainer.eval 'cookie', (cookie) =>
        if cookie.get('cord_require_stat_collection_enabled')
          result.done =>
            Future.all [
              Future.require('jquery', 'cord!css/browserManager', 'cord!router/clientSideRouter')
              Future.timeout(3000)
            ]
            .spread ([$, cssManager, router]) =>
              keys = Object.keys(require.s.contexts._.defined)
              re = /^cord(-\w)?!/
              keys = _.filter keys, (name) ->
                not re.test(name)
              $.post '/REQUIRESTAT/collect',
                root: router.getActualPath()
                definedModules: keys
                css: cssManager._loadingOrder
              .done (resp) ->
                $('body').addClass('cord-require-stat-collected')
                console.warn "/REQUIRESTAT/collect response", resp

      @_widgetOrder = null
      result


    bind: (widgetId) ->
      if @widgets[widgetId]?
        w = @widgets[widgetId].widget
        w.initBehaviour().andThen ->
          w.markShown(ignoreChildren = true)
      else
        Future.rejected(new Error("Try to use uninitialized widget with id = #{widgetId}"))


    getById: (id) ->
      ###
      Returns widget with the given id if it is exists.
      Throws exception otherwise.
      @param String id widget id
      @return Widget
      ###

      if @widgets[id]?
        @widgets[id].widget
      else
        throw new Error("Try to get uninitialized widget with id = #{id}")


    subscribePushBinding: (parentWidgetId, ctxName, childWidget, paramName, ctxVersionBorder) ->
      ###
      Subscribes child widget to the parent widget's context variable change event
      @browser-only
      @param String parentWidgetId id of the parent widget
      @param String ctxName name of parent's context variable whose changes we are listening to
      @param Widget childWidget subscribing child widget object
      @param String paramName name of child widget's param which should be set to the context variable value
      @return postal subscription object
      ###
      subscription = postal.subscribe
        topic: "widget.#{ parentWidgetId }.change.#{ ctxName }"
        callback: (data) ->
          if not childWidget.isSentenced() \
              # if data.version is undefined than it's model-emitted event and need not version check
              and (not ctxVersionBorder? or not data.version? or data.version > ctxVersionBorder) \
              and not data.stashed
            params = {}

            # param with name "params" is a special case and we should expand the value as key-value pairs
            # of widget's params
            if paramName == 'params'
              if _.isObject data.value
                for subName, subValue of data.value
                  params[subName] = subValue
              else
                # todo: warning?
            else
              params[paramName] = data.value

#            _console.log "#{ envelope.topic } -> #{ childWidget.debug(paramName) } -> #{ data.value }"
            deferAggregator.setWidgetParams childWidget, params
      childWidget.addSubscription subscription
      subscription


    getActiveTransition: ->
      @_activeTransitionPromise


    resetSmartTransition: ->
      ###
      Resets current transition state to avoid deadlock when router.navigate is called during current smart transition.
      ###
      @_inTransition = false


    smartTransitPage: (newRootWidgetPath, params, transition) ->
      ###
      Initiates client-side transition of the page.
      Calls transitPage() method but prevents two transitPages to be executed concurrently. If more than one
       transitPage() is called during current incomplete transition then only last call is performed, all others are
       skipped.
      @browser-only
      @param String newRootWidgetPath canonical path of the new root page-widget
      @param Map params params for the new root widget
      @param PageTransition transition page transition support object which contains information about transition and
                                       triggers events related to transition process
      @return Future
      ###
      if not @_inTransition
        prevRoot = @rootWidget
        @_inTransition = true
        @_activeTransitionPromise = thisTransitionPromise = Future.single("smartTransitPage -> #{newRootWidgetPath}")
        @transitPage(newRootWidgetPath, params, transition).then (res) =>
          # the promise may be completed by the clientSideRouter.redirect() method, so this guard is necessary
          if not thisTransitionPromise.completed() and @_activeTransitionPromise == thisTransitionPromise
            @_inTransition = false
            thisTransitionPromise.resolve(res)
            # activate GC only if no transtition is waiting to be processed
            # also don't GC if the root widget type hasn't changed (known to cause wrong widgets to be collected)
            @gcWidgets() if not @_nextTransitionCallback and prevRoot.constructor != @rootWidget.constructor
          return
        .catch (err) =>
          if not thisTransitionPromise.completed() and @_activeTransitionPromise == thisTransitionPromise
            @_inTransition = false
            thisTransitionPromise.reject(err)
        # avoiding infinite hanging of navigation due to never-completing transition promise
        thisTransitionTimeout = setTimeout ->
          if not thisTransitionPromise.completed()
            @_inTransition = false
            thisTransitionPromise.reject(new Error("Transition to '#{newRootWidgetPath}' timed out!"))
        , 15000
        thisTransitionPromise.finally ->
          clearTimeout(thisTransitionTimeout)
      else
        if not @_nextTransitionCallback?
          @_nextTransitionPromise = @_activeTransitionPromise.then =>
            @_nextTransitionCallback()
          .catch (err) =>
            # check if error ocurred in then-callback above
            if @_nextTransitionCallback
              @_nextTransitionCallback()
            else
              throw err
        # overriding previously set callback to skip intermediate navigation trials performed during active navigation
        @_nextTransitionCallback = =>
          @_inTransition = false # do not remove to avoid infinite loop!
          @_nextTransitionCallback = null
          @smartTransitPage(newRootWidgetPath, params, transition)
        @_nextTransitionPromise


    transitPage: (newRootWidgetPath, params, transition, catchErrors = true) ->
      ###
      Initiates client-side transition of the page.
      This means smart changing of the layout of the page and re-rendering the widget according to the given new
       root widget and it's params.
      @browser-only
      @param String newRootWidgetPath canonical path of the new root page-widget
      @param Map params params for the new root widget
      @param PageTransition transition page transition support object which contains information about transition and
                                       triggers events related to transition process
      @return Future
      ###
      if global.config.debug.widget
        _console.log "WidgetRepo::transitPage -> #{newRootWidgetPath}, current root = #{ @rootWidget.debug() }"

      # interrupting previous transition if it's not completed
#      @_curTransition.interrupt() if @_curTransition? and @_curTransition.isActive()
#      @_curTransition = transition

      oldRootWidget = @rootWidget
      oldExtendList = _.clone(@_currentExtendList)

      @_rebuildExtendTree(newRootWidgetPath).spread (newRootWidget, commonExistingWidget, commonWidgetName) =>
        # if the new root widget is already exists in the current page structure
        if newRootWidget == commonExistingWidget
          if oldRootWidget != newRootWidget
            # if the new root widget exists in the current structure but it's not a root widget, than we need
            # to unbind it from the old (parent) root widget, eliminate impact of the old root widget to the placeholders
            # of the new root (because the old root extends from the new one directly or indirectly)
            # and push new params into the new root widget
            newRootWidget.getStructTemplate().then (tmpl) =>
              tmpl.assignWidget(tmpl.struct.ownerWidget, newRootWidget)
              tmpl.replacePlaceholders(tmpl.struct.ownerWidget, newRootWidget.ctx[':placeholders'], transition)
            .then ->
              newRootWidget.setParamsSafe(params)
            .then =>
              @dropWidget(oldRootWidget.ctx.id)
              transition.complete()
          else
            # if the new widget is the same as the current root, than this is just params change and we should only push
            # new params to the root widget
            newRootWidget.setParamsSafe(params)
        else
          # if the new root widget doesn't exist in the current page structure, than we need to create it,
          # inject to the top of the page structure and recursively find the common widget from the extend list
          # down to the base widget (containing <html> tag)
          newRootWidget.inject(params, commonExistingWidget, transition).then (commonBaseWidget) =>
            @dropWidget(oldRootWidget.ctx.id) if oldRootWidget and commonBaseWidget != oldRootWidget
            newRootWidget.shown().done -> transition.complete()
          .catch (e) =>
            ###
            Perform rollback operations of this transition:
              - rollback root widget to the old one
              - unbind a commonExistingWidget from widget which attached to
              - restore extend list
              - register commonExistingWidget to old widget
            ###
            @setRootWidget(oldRootWidget)
            @_currentExtendList[@_currentExtendList.indexOf(commonExistingWidget)-1].unbindChild(commonExistingWidget)
            oldExtendList[oldExtendList.indexOf(commonExistingWidget)-1].registerChild(commonExistingWidget, commonWidgetName)
            @_currentExtendList = oldExtendList
            throw e
      .catchIf errors.MustReloadPage, (e) =>
        throw e if not catchErrors
        location.reload()
      .catchIf errors.MustTransitPage, (e) =>
        throw e if not catchErrors
        @transitPage(e.widget, e.params, transition)
      .catchIf (-> catchErrors), (err) =>
        # If there is error widget, transit to it
        AppConfigLoader.ready().then (appConfig) =>
          if appConfig.errorWidget
            @transitPage(appConfig.errorWidget, Utils.buildErrorWidgetParams(err, newRootWidgetPath, params), transition, false)
            .catch (err1) =>
              if err1 instanceof errors.MustReloadPage
                throw new Error("FATAL: Error widget should have common widget in parents with #{newRootWidgetPath}")
              else
                throw err1
            .failAloud('Error widget rendering error')

          else
            throw err
      .failAloud("WidgetRepo::transitPage(\"#{newRootWidgetPath}\")")



    _rebuildExtendTree: (newRootWidgetPath) ->
      ###
      Smartly reconstructs page's widget extend tree based on given new root widget path.
      Btw created new extend tree widgets, set new root widget.
      @param {String} newRootWidgetPath
      @return {Future[Tuple[Widget, Widget]]} new root widget and common base widget (between old and new page)
      ###
      oldRootWidget = @rootWidget
      @_calculateNewExtendTree(newRootWidgetPath).spread (newWidgetsList, commonExistingWidget, commonWidgetName) =>
        newRootWidget =
          if newWidgetsList.length
            newWidgetsList[0]
          else
            commonExistingWidget

        if oldRootWidget != newRootWidget
          keepFrom = @_currentExtendList.indexOf(commonExistingWidget)
          @_currentExtendList = newWidgetsList.concat(@_currentExtendList.slice(keepFrom))

          @setRootWidget(newRootWidget)
          if newWidgetsList.length
            newWidgetsList[newWidgetsList.length - 1].registerChild(commonExistingWidget, commonWidgetName)

        [[newRootWidget, commonExistingWidget, commonWidgetName]]


    _calculateNewExtendTree: (extendWidgetPath) ->
      ###
      Initiates recursive search of common extend widget for the given widget path.
      @param {String} extendWidgetPath
      @return {Future[Tuple[Array[Widget], Widget, String]]} newly added extend widget list,
                                                             common existing widget and it's name
      ###
      existingWidget = _.find @_currentExtendList, (x) -> x.getPath() == extendWidgetPath
      if existingWidget
        Future.resolved([[], existingWidget])
      else
        @createWidget(extendWidgetPath).then (widget) =>
          widget.getStructTemplate().then (tmpl) =>
            if not tmpl.isEmpty() and tmpl.struct.extend
              @_recScanExtendTree(tmpl).spread (newWidgetsList, commonExistingWidget, commonWidgetName) ->
                [[[widget].concat(newWidgetsList), commonExistingWidget, commonWidgetName]]
            else
              throw new errors.MustReloadPage


    _recScanExtendTree: (structTmpl) ->
      ###
      As _calculateNewExtendTree but accepts prepared structure template.
      ###
      extendWidgetRefId = structTmpl.struct.extend.widget
      extendWidgetInfo = structTmpl.struct.widgets[extendWidgetRefId]
      extendWidgetPath = extendWidgetInfo.path
      existingWidget = _.find @_currentExtendList, (x) -> x.getPath() == extendWidgetPath
      if existingWidget
        Future.resolved([[], existingWidget, extendWidgetInfo.name])
      else
        structTmpl.createWidgetByRefId(extendWidgetRefId).then (widget) =>
          widget.getStructTemplate().then (tmpl) =>
            if not tmpl.isEmpty() and tmpl.struct.extend
              @_recScanExtendTree(tmpl).spread (newWidgetsList, commonExistingWidget, commonWidgetName) ->
                [[[widget].concat(newWidgetsList), commonExistingWidget, commonWidgetName]]
            else
              throw new errors.MustReloadPage

define [
  'cord!Collection'
  'cord!configPaths'
  'cord!Context'
  'cord!css/helper'
  'cord!isBrowser'
  'cord!Model'
  'cord!Module'
  'cord!StructureTemplate'
  'cord!templateLoader'
  'cord!utils/Future'
  'dustjs-helpers'
  'monologue' + (if document? then '' else '.js')
  'postal'
  'underscore'
], (Collection, configPaths, Context, cssHelper, isBrowser, Model, Module,StructureTemplate, templateLoader, Future,
    dust, Monologue, postal, _) ->

  dust.onLoad = (tmplPath, callback) ->
    templateLoader.loadTemplate tmplPath, ->
      callback null, ''


  class Widget extends Module
    @include Monologue.prototype

    # Enable special mode for building structure tree of widget
    compileMode: false

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

    _modelBindings: null

    _subscribeOnAnyChild: null

    @initParamRules: ->
      ###
      Prepares rules for handling incoming params of the widget.
      Converts params static attribute of the class into _paramRules array which defines behaviour of processParams
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


    getPath: ->
      @constructor.path

    getDir: ->
      @constructor.relativeDirPath

    getBundle: ->
      @constructor.bundle


    constructor: (params) ->
      ###
      Constructor

      Accepted params:
      * context (Object) - inject widget's context explicitly (should re used only to restore widget's state on node-browser
                           transfer
      * repo (WidgetRepo) - inject widget repository (should be always set except in compileMode
      * compileMode (boolean) - turn on/off special compile mode of the widget (default - false)
      * extended (boolean) - mark widget as part of extend tree (default - false)

      @param (optional)Object params custom params, accepted by widget
      ###

      if not @constructor._paramRules? and (@constructor.params? or @constructor.initialCtx?) # may be initialCtx is not necessary here
        @constructor.initParamRules()

      @_modelBindings = {}
      if params?
        if params.context?
          if params.context instanceof Context
            @ctx = params.context
          else
            @ctx = new Context(params.context)
        @setRepo params.repo if params.repo?
        @setServiceContainer params.serviceContainer if params.serviceContainer?
        @compileMode = params.compileMode if params.compileMode?
        @_isExtended = params.extended if params.extended?
        @_modelBindings = params.modelBindings if params.modelBindings?

      @_postalSubscriptions = []
      @resetChildren()

      if not @ctx?
        if @compileMode
          id = 'rwdt-' + _.uniqueId()
        else
          id = (if isBrowser then 'b' else 'n') + 'wdt-' + _.uniqueId()
        @ctx = new Context(id, @constructor.initialCtx)


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
        @behaviour = null
      @cleanSubscriptions()
      @_postalSubscriptions = []
      @_modelBindings = {}


    addSubscription: (subscription) ->
      ###
      Register event subscription associated with the widget.

      All such subscritiptions need to be registered to be able to clean them up later (see @cleanChildren())
      ###
      @_postalSubscriptions.push subscription


    cleanSubscriptions: ->
      subscription.unsubscribe() for subscription in @_postalSubscriptions
      for name, mb of @_modelBindings
        mb.subscription?.unsubscribe()


    setRepo: (repo) ->
      ###
      Inject widget repository to create child widgets in same repository while rendering the same page.
      The approach is one repository per request/page rendering.
      @param WidgetRepo repo the repository
      ###
      @widgetRepo = repo


    setServiceContainer: (serviceContainer) =>
      @container = serviceContainer


    getServiceContainer: =>
      @container


    _registerModelBinding: (name, value) ->
      ###
      Handles situation when widget's incoming param is model of collection.
      @param String name param name
      @param Any value param value which should be checked to be model or collection and handled accordingly
      ###
      if isBrowser and @_modelBindings[name]?
        mb = @_modelBindings[name]
        if value != mb.model
          if mb.subscription?
            mb.subscription.unsubscribe()
          delete @_modelBindings[name]
      if value instanceof Model or value instanceof Collection
        @_modelBindings[name] ?= {}
        @_modelBindings[name].model = value


    processParams: (params, callback) ->
      ###
      Main "reactor" to the widget's API params change from outside.
      Changes widget's context variables according to the rules, defined in "params" static configuration of the widget.
      Rules are applied only to defined input params.
      @param Object params changed params
      @param (optional)Function callback function to be called after processing.
      ###

      console.log "#{ @debug 'processParams' } -> ", params if global.CONFIG.debug?.widget
      rules = @constructor._paramRules
      processedRules = {}
      specialParams = ['match', 'history', 'shim', 'trigger', 'params']
      for name, value of params
        if rules[name]?
          for rule in rules[name]
            if rule.hasValidation and not rule.validate(value)
              throw "Validation of param '#{ name }' of widget #{ @debug() } is not passed!"
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
        else if specialParams.indexOf(name) == -1
          throw "Widget #{ @getPath() } is not accepting param with name #{ name }!"
      callback?()


    _handleOnShow: (callback) ->
      if @onShow?
        if @onShow(callback) != ':block'
          callback()
      else
        callback()


    #
    # Main method to call if you want to show rendered widget template
    # @public
    # @final
    #
    show: (params, callback) ->
      @_doAction 'default', params, =>
        console.log "#{ @debug 'show' } -> params:", params, " context:", @ctx if global.CONFIG.debug?.widget
        @_handleOnShow =>
          @renderTemplate callback

    showJson: (params, callback) ->
      @_doAction 'default', params, =>
        console.log "#{ @debug 'showJson' } -> params:", params, " context:", @ctx if global.CONFIG.debug?.widget
        @_handleOnShow =>
          @renderJson callback


    _doAction: (action, params, callback) ->
      if @constructor.params? or @constructor.initialCtx?
        @processParams params, callback
      else if @["_#{ action }Action"]?
        console.warn "WARNING: Old style actions (#{ @debug '_defaultAction()' }) are deprecated! You should refactor your code!"
        called = false
        wrappedCallback = =>
          called = true
          callback()
        if @["_#{ action }Action"](params, wrappedCallback) != 'block' and not called
          callback()
      else
        callback()


    fireAction: (action, params) ->
      ###
      Just call action (change context) and do not output anything
      ###
      @_doAction action, params, =>
        console.log "#{ @debug 'fireAction' } -> ", params #, " context:", @ctx


    renderJson: (callback) ->
      callback null, JSON.stringify(@ctx)


    getTemplatePath: ->
      "#{ @getDir() }/#{ @constructor.dirName }.html"


    cleanChildren: ->
      if @children.length
        if @_structTemplate? and @_structTemplate != ':empty'
          @_structTemplate.unassignWidget widget for widget in @children
        @widgetRepo.dropWidget(widget.ctx.id) for widget in @children
        @resetChildren()


    sentenceChildrenToDeath: ->
      child.sentenceToDeath() for child in @children


    sentenceToDeath: ->
      @cleanSubscriptions()
      @_sentenced = true
      @sentenceChildrenToDeath()


    isSentenced: ->
      @_sentenced?


    compileTemplate: (callback) ->
      if not @compileMode
        callback 'not in compile mode', ''
      else
        @inlineCounter = 0 # for generating inline block IDs
        tmplPath = @getPath()
        tmplFullPath = "./#{ configPaths.PUBLIC_PREFIX }/bundles/#{ @getTemplatePath() }"
        require ['fs'], (fs) =>
          fs.readFile tmplFullPath, (err, data) =>
            throw err if err
            @compiledSource = dust.compile(data.toString(), tmplPath)
            fs.writeFile "#{ tmplFullPath }.js", @compiledSource, (err)->
              throw err if err
              console.log "Template saved: #{ tmplFullPath }.js"
            if @getPath() != '/cord/core//Switcher'
              dust.loadSource @compiledSource
              dust.render tmplPath, @getBaseContext().push(@ctx), callback
            else
              callback(null, '')


    getStructTemplate: (callback) ->
      if @_structTemplate?
        callback @_structTemplate
      else
        tmplStructureFile = "bundles/#{ @getTemplatePath() }.structure.json"
        returnCallback = =>
          struct = dust.cache[tmplStructureFile]
          if struct.widgets? and Object.keys(struct.widgets).length > 1
            @_structTemplate = new StructureTemplate struct, this
          else
            @_structTemplate = ':empty'
          callback @_structTemplate

        if dust.cache[tmplStructureFile]?
          returnCallback()
        else
          require ["text!#{ tmplStructureFile }"], (jsonString) =>
            dust.register tmplStructureFile, JSON.parse(jsonString)
            returnCallback()

    injectAction: (action, params, callback) ->
      ###
      @browser-only
      ###

      @widgetRepo.registerNewExtendWidget this

      @_doAction action, params, =>
        console.log "injectAction #{ @getPath() }::_#{ action }Action: params:", params, " context:", @ctx
        @_handleOnShow =>
          @getStructTemplate (tmpl) =>
            @_injectRender tmpl, callback


    _injectRender: (tmpl, callback) ->
      ###
      @browser-only
      ###

      extendWidgetInfo = if tmpl != ':empty' then tmpl.struct.extend else null
      if extendWidgetInfo?
        extendWidget = @widgetRepo.findAndCutMatchingExtendWidget tmpl.struct.widgets[extendWidgetInfo.widget].path
        if extendWidget?
          tmpl.assignWidget extendWidgetInfo.widget, extendWidget
          tmpl.replacePlaceholders extendWidgetInfo.widget, extendWidget.ctx[':placeholders'], =>
            @registerChild extendWidget
            @resolveParamRefs extendWidget, extendWidgetInfo.params, (params) ->
              extendWidget.fireAction 'default', params
              callback extendWidget
        else
          tmpl.getWidget extendWidgetInfo.widget, (extendWidget) =>
            @registerChild extendWidget
            @resolveParamRefs extendWidget, extendWidgetInfo.params, (params) ->
              extendWidget.injectAction 'default', params, callback
      else
        if true
          location.reload()
        else
          # This is very hackkky attempt to replace full page body without reloading.
          # It works ok some times, but soon requirejs begin to fail to load new scripts for the page.
          # So I decided to leave this code for the promising future and fallback to force page reload as for now.
          console.log "FULL PAGE REWRITE!!! struct tmpl: ", tmpl
          @widgetRepo.replaceExtendTree()
          @renderTemplate (err, out) =>
            if err then throw err
            document.open()
            document.write out
            document.close()
            require ['cord!/cord/core/router/clientSideRouter', 'jquery'], (router, $) ->
              $.cache = {}
              $(window).unbind()
              #$(document).unbind()
              router.initNavigate()
            callback()


    renderTemplate: (callback) ->
      ###
      Decides wether to call extended template parsing of self-template parsing and calls it.
      ###
      console.log @debug('renderTemplate') if global.CONFIG.debug?.widget

      @getStructTemplate (tmpl) =>
        if tmpl != ':empty' and tmpl.struct.extend?
          @_renderExtendedTemplate tmpl, callback
        else
          @_renderSelfTemplate callback


    _renderSelfTemplate: (callback) ->
      ###
      Usual way of rendering template via dust.
      ###
      console.log @debug('_renderSelfTemplate') if global.CONFIG.debug?.widget

      tmplPath = @getPath()

      actualRender = =>
        @markRenderStarted()
        @cleanChildren()
        dust.render tmplPath, @getBaseContext().push(@ctx), callback
        @markRenderFinished()

      if dust.cache[tmplPath]?
        actualRender()
      else
        templateLoader.loadWidgetTemplate tmplPath, ->
          actualRender()


    resolveParamRefs: (widget, params, callback) ->
      # this is necessary to avoid corruption of original structure template params
      params = _.clone params

      # removing special params
      delete params.placeholder
      delete params.type
      delete params.class
      delete params.name

      waitCounter = 0
      waitCounterFinish = false

      bindings = {}

      # waiting for parent's necessary context-variables availability before rendering widget...
      for name, value of params
        if name != 'name' and name != 'type'

          if typeof value is 'string' and value.charAt(0) == '^'
            value = value.slice 1
            bindings[value] = name

            # if context value is deferred, than waiting asyncronously...
            if @ctx.isDeferred value
              waitCounter++
              @subscribeValueChange params, name, value, ->
                waitCounter--
                if waitCounter == 0 and waitCounterFinish
                  callback params

            # otherwise just getting it's value syncronously
            else
              # param with name "params" is a special case and we should expand the value as key-value pairs
              # of widget's params
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


    _renderExtendedTemplate: (tmpl, callback) ->
      ###
      Render template if it uses #extend plugin to extend another widget
      @param StructureTemplate tmpl structure template object
      @param Function(err, output) callback
      ###

      extendWidgetInfo = tmpl.struct.extend

      tmpl.getWidget extendWidgetInfo.widget, (extendWidget) =>
        extendWidget._isExtended = true if @_isExtended
        @registerChild extendWidget, extendWidgetInfo.name
        @resolveParamRefs extendWidget, extendWidgetInfo.params, (params) ->
          extendWidget.show params, callback


    renderInline: (inlineName, callback) ->
      ###
      Renders widget's inline-block by name
      ###
      console.log "#{ @constructor.name }::renderInline(#{ inlineName })" if global.CONFIG.debug?.widget

      if @ctx[':inlines'][inlineName]?
        template = @ctx[':inlines'][inlineName].template
        tmplPath = "#{ @getDir() }/#{ template }"

        actualRender = =>
          dust.render tmplPath, @getBaseContext().push(@ctx), callback

        if dust.cache[tmplPath]?
          actualRender()
        else
          # todo: load via cord-t
          require ["text!bundles/#{ tmplPath }"], (tmplString) =>
            dust.loadSource tmplString, tmplPath
            actualRender()
      else
        throw "Trying to render unknown inline (name = #{ inlineName })!"


    renderRootTag: (content) ->
      ###
      Builds and returns correct html-code of the widget's root tag with the given rendered contents.
      @param String content rendered template of the widget
      @return String
      ###
      classString = @_buildClassString()
      classAttr = if classString.length then ' class="' + classString + '"' else ''
      "<#{ @rootTag } id=\"#{ @ctx.id }\"#{ classAttr }>#{ content }</#{ @rootTag }>"


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


    _buildClassString: ->
      classList = []
      classList.push(@cssClass) if @cssClass
      classList.push(@ctx._modifierClass) if @ctx._modifierClass
      classList.join(' ')


    setModifierClass: (cls) ->
      ###
      Save modifier classes came from the template in the state of the widget.
      Need it to be able to restore when widget is re-rendered and the root tag is recreated.
      @param String class space-separeted list of css class-names
      ###
      @ctx._modifierClass = cls


    _renderPlaceholder: (name, callback) ->
      placeholderOut = []
      returnCallback = ->
        callback(placeholderOut.join '')

      waitCounter = 0
      waitCounterFinish = false

      i = 0
      placeholderOrder = {}
      phs = @ctx[':placeholders'] ? []
      ph = phs[name] ? []

      for info in ph
        do (info) =>
          widgetId = info.widget
          widget = @widgetRepo.getById(widgetId)
          widget.setModifierClass(info.class) if info.type != 'inline'

          timeoutTemplateOwner = info.timeoutTemplateOwner
          delete info.timeoutTemplateOwner

          renderTimeoutTemplate = ->
            tmplPath = "#{ timeoutTemplateOwner.getDir() }/#{ info.timeoutTemplate }"

            actualRender = ->
              dust.render tmplPath, timeoutTemplateOwner.getBaseContext().push(timeoutTemplateOwner.ctx), (err, out) ->
                if err then throw err
                placeholderOut[placeholderOrder[widgetId]] = widget.renderRootTag(out)
                waitCounter--
                if waitCounter == 0 and waitCounterFinish
                  returnCallback()

            if dust.cache[tmplPath]?
              actualRender()
            else
              # todo: load via cord-t
              require ["text!bundles/#{ tmplPath }"], (tmplString) =>
                dust.loadSource tmplString, tmplPath
                actualRender()

          if info.type == 'widget'
            placeholderOrder[widgetId] = i

            waitCounter++

            complete = false
            widget.show info.params, (err, out) ->
              if err then throw err
              if not complete
                complete = true
                placeholderOut[placeholderOrder[widgetId]] = widget.renderRootTag(out)

                waitCounter--
                if waitCounter == 0 and waitCounterFinish
                  returnCallback()
              else
                require ['cord!utils/DomHelper'], (DomHelper) ->
                  DomHelper.insertHtml widgetId, out, ->
                    widget._delayedRender = false
                    widget.browserInit()

            if isBrowser and info.timeout? and info.timeout > 0
              setTimeout ->
                if not complete
                  complete = true
                  widget._delayedRender = true
                  if info.timeoutTemplate?
                    renderTimeoutTemplate()
                  else
                    placeholderOut[placeholderOrder[widgetId]] =
                      widget.renderRootTag('<b>Hardcode Stub Text!!</b>')
                    waitCounter--
                    if waitCounter == 0 and waitCounterFinish
                      returnCallback()

              , info.timeout

          else if info.type == 'timeouted-widget'
            placeholderOrder[widgetId] = i

            widget._delayedRender = true
            if info.timeoutTemplate?
              waitCounter++
              renderTimeoutTemplate()
            else
              placeholderOut[placeholderOrder[widgetId]] =
                widget.renderRootTag('<b>Hardcode Stub Text!!</b>')

            subscription = postal.subscribe
              topic: "widget.#{ widgetId }.deferred.ready"
              callback: (params) ->
                widget.show params, (err, out) ->
                  if err then throw err
                  require ['cord!utils/DomHelper'], (DomHelper) ->
                    DomHelper.insertHtml widgetId, out, ->
                      widget._delayedRender = false
                      widget.browserInit()
                subscription.unsubscribe()

          else
            placeholderOrder[info.template] = i

            inlineId = "inline-#{ widget.ctx.id }-#{ info.name }"
            classAttr = info.class ? ''
            classAttr = if classAttr then "class=\"#{ classAttr }\"" else ''
            waitCounter++
            widget.ctx[':inlines'] ?= {}
            widget.ctx[':inlines'][info.name] =
              id: inlineId
              template: info.template
            widget.renderInline info.name, (err, out) ->
              if err then throw err
              placeholderOut[placeholderOrder[info.template]] = "<#{ info.tag } id=\"#{ inlineId }\"#{ classAttr }>#{ out }</#{ info.tag }>"
              waitCounter--
              if waitCounter == 0 and waitCounterFinish
                returnCallback()
          i++

      waitCounterFinish = true
      if waitCounter == 0
        returnCallback()


    _getPlaceholderDomId: (name) ->
      'ph-' + @ctx.id + '-' + name


    definePlaceholders: (placeholders) ->
      @ctx[':placeholders'] = placeholders


    replacePlaceholders: (placeholders, structTmpl, replaceHints, callback) ->
      ###
      Replaces contents of the placeholders of this widget according to the given params
      @browser-only
      @param Object placeholders meta-information about new placeholders contents
      @param StructureTemplate structTmpl structure template of the calling widget
      @param Object replaceHints pre-calculated helping information about which placeholders should be replaced
                                 and which should not
      @param Function() callback callback which should be called when replacement is done (async)
      ###

      require ['jquery', 'cord!utils/DomHelper'], ($, DomHelper) =>
        waitCounter = 0
        waitCounterFinish = false

        reduceWaitCounter = ->
          waitCounter--
          if waitCounter == 0 and waitCounterFinish
            callback()

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

        for name, items of ph
          do (name) =>
            if replaceHints[name].replace
              waitCounter++
              @_renderPlaceholder name, (out) =>
                try
                  DomHelper.insertHtml @_getPlaceholderDomId(name), out, reduceWaitCounter
                catch e
                  console.log "WARNING: Trying to replace unexistent placeholder with name \"#{ name }\" " +
                    "in widget #{ @debug() }"
                  reduceWaitCounter()
            else
              i = 0
              for item in items
                do (item, i) =>
                  widget = @widgetRepo.getById item.widget
                  waitCounter++
                  widget.replaceModifierClass(item.class)
                  structTmpl.replacePlaceholders replaceHints[name].items[i], widget.ctx[':placeholders'], ->
                    widget.fireAction 'default', item.params
                    reduceWaitCounter()
                i++

        waitCounterFinish = true
        if waitCounter == 0
          callback()


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


    getInitCss: (alreadyAdded) ->
      ###
      Generates html head fragment with css-link tags that should be included for server-side generated page
      @param (optional)Object alreadyAdded hash with list of already included css-files to avoid duplicate link-tags
      @return String
      ###
      alreadyAdded ?= {}
      addCss = []
      for css in @getCssFiles()
        if not alreadyAdded[css]
          addCss.push css
          alreadyAdded[css] = true
      html = (cssHelper.getHtmlLink(css) for css in addCss).join ''
      "#{ (widget.getInitCss(alreadyAdded) for widget in @children).join '' }#{ html }"


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


    loadCss: ->
      ###
      Load widget's css-files to the current page.
      @browser-only
      ###
      require ['cord!css/browserManager'], (cssManager) =>
        cssManager.load cssFile for cssFile in @getCssFiles()


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


    registerChild: (child, name) ->
#      console.log "#{ @debug 'registerChild' } -> #{ child.debug() }"
      @children.push child
      @childById[child.ctx.id] = child
      @childByName[name] = child if name?
      @widgetRepo.registerParent child, this


    unbindChild: (child) ->
      ###
      Removes the given widget from the list of children on the current widget
      @param Widget child child widget object
      ###
      index = @children.indexOf child
      if index != -1
        @children.splice index, 1
        delete @childById[child.ctx.id]
        for name, widget of @childByName
          if widget == child
            delete @childByName[name]
      else
        throw "Trying to remove unexistent child of widget #{ @constructor.name }(#{ @ctx.id }), child: #{ child.constructor.name }(#{ child.ctx.id })"


    getBehaviourClass: ->
      if not @behaviourClass?
        @behaviourClass = "#{ @constructor.name }Behaviour"

      if @behaviourClass == false
        null
      else
        @behaviourClass

    #Special selector for children ':any' - subscribes on all child widgets
    bindChildEvents: ->
      if @constructor.childEvents?
        for eventDef, callback of @constructor.childEvents
          eventDef = eventDef.split ' '
          childName = eventDef[0]
          topic = eventDef[1]
          if _.isString callback
            if @[callback]
              name = callback
              callback =  @[callback]
              if not _.isFunction callback
                throw new Error("Callback #{ name } is not a function")
            else
              throw new Error("Callback #{ callback } doesn't exist")
          else if not _.isFunction callback
            throw new Error("Invalid child widget callback definition: [#{ childName }, #{ topic }]")

          if childName == ':any'
            @_subscribeOnAnyChild = [] if !@_subscribeOnAnyChild
            @_subscribeOnAnyChild.push {topic: topic, callback:callback}

            for child of @childById
              @childById[child].on(topic, callback).withContext(this)
          else
            if @childByName[childName]?
              @childByName[childName].on(topic, callback).withContext(this)
            else
              throw new Error("Trying to subscribe for event '#{ topic }' of unexistent child with name '#{ childName }'")


    bindModelEvents: ->
      ###
      Subscribes to model events for model-params came to widget.
      ###
      rules = @constructor._paramRules
      for name, mb of @_modelBindings
        if not mb.subscription? and rules[name]?
          do (name) =>
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
              true# stub


    initBehaviour: ($domRoot) ->
      ###
      Correctly (re)creates the behaviour instance for the widget if there is defined behaviour
      @browser-only
      @param jQuery $domRoot injected DOM root for the widget
      ###
      if @behaviour?
        @behaviour.clean()
        @behaviour = null

      behaviourClass = @getBehaviourClass()

      if behaviourClass
        require ["cord!/#{ @getDir() }/#{ behaviourClass }"], (BehaviourClass) =>
          if BehaviourClass instanceof Function
            @behaviour = new BehaviourClass(this, $domRoot)
          else
            console.err 'WRONG BEHAVIOUR CLASS:', behaviourClass

      @loadCss()


    createChildWidget: (type, name, callback) ->
      ###
      Dynamically creates new child widget with the given canonical type
      @param String type new widget type (absolute or in context of the current widget)
      @param (optional)String name optional name for the new widget
      @param Function(Widget) callback callback function to pass resulting child widget
      ###
      if _.isFunction(name)
        callback = name
        name = null

      @widgetRepo.createWidget type, @getBundle(), (child) =>
        @registerChild(child, name)
        if @_subscribeOnAnyChild
          for option in @_subscribeOnAnyChild
            child.on(option.topic, option.callback).withContext(this)
        callback(child)


    browserInit: (stopPropagateWidget, $domRoot) ->
      ###
      Almost copy of widgetRepo::init but for client-side rendering
      @browser-only
      @param (optional)Widget stopPropageteWidget widget for which method should stop pass browserInit to child widgets
      @param (optional)jQuery domRoot injected DOM root for the widget or it's children
      ###

      if stopPropagateWidget? and not (stopPropagateWidget instanceof Widget)
        $domRoot = stopPropagateWidget
        stopPropagateWidget = undefined

      if this != stopPropagateWidget and not @_delayedRender
        @bindChildEvents()
        @bindModelEvents()

        for widgetId, bindingMap of @childBindings
          @widgetRepo.getById(widgetId).cleanSubscriptions()
          for ctxName, paramName of bindingMap
            @widgetRepo.subscribePushBinding @ctx.id, ctxName, @childById[widgetId], paramName

        for childWidget in @children
          if not childWidget.behaviour?
            childWidget.browserInit(stopPropagateWidget, $domRoot)

        @initBehaviour($domRoot)

        @emit 'render.complete'


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


    # should not be used directly, use getBaseContext() for lazy loading
    _baseContext: null

    getBaseContext: ->
      @_baseContext ? (@_baseContext = @_buildBaseContext())


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


    _buildBaseContext: ->
      if @compileMode
        @_buildCompileBaseContext()
      else
        @_buildNormalBaseContext()

    _buildNormalBaseContext: ->
      dust.makeBase

        widget: (chunk, context, bodies, params) =>
          ###
          {#widget/} block handling
          ###
          @childWidgetAdd()
          chunk.map (chunk) =>
            callbackRender = (widget) =>
              @registerChild widget, params.name
              @resolveParamRefs widget, params, (actionParams) =>
                widget.setModifierClass(params.class)
                widget.show actionParams, (err, out) =>
                  @childWidgetComplete()
                  if err then throw err
                  chunk.end widget.renderRootTag(out)

            if bodies.block?
              @getStructTemplate (tmpl) ->
                tmpl.getWidgetByName params.name, callbackRender
            else
              @widgetRepo.createWidget params.type, @getBundle(), callbackRender


        deferred: (chunk, context, bodies, params) =>
          deferredKeys = params.params.split /[, ]/
          needToWait = (name for name in deferredKeys when @ctx.isDeferred(name))

          # there are deferred params, handling block async...
          if needToWait.length > 0
            promise = new Future
            for name in needToWait
              do (name) =>
                promise.fork()
                subscription = postal.subscribe
                  topic: "widget.#{ @ctx.id }.change.#{ name }"
                  callback: (data) ->
                    if data.value != ':deferred'
                      promise.resolve()
                      subscription.unsubscribe()
            chunk.map (chunk) ->
              promise.done ->
                chunk.render bodies.block, context
                chunk.end()
          # no deffered params, parsing block immedialely
          else
            chunk.render bodies.block, context


        #
        # Placeholder - point of extension of the widget
        #
        placeholder: (chunk, context, bodies, params) =>
          @childWidgetAdd()
          chunk.map (chunk) =>
            name = params?.name ? 'default'
            @_renderPlaceholder name, (out) =>
              @childWidgetComplete()
              chunk.end "<div id=\"#{ @_getPlaceholderDomId name }\">#{ out }</div>"

        #
        # Widget initialization script generator
        #
        widgetInitializer: (chunk, context, bodies, params) =>
          if @widgetRepo._initEnd
            ''
          else
            chunk.map (chunk) =>
              subscription = postal.subscribe
                topic: "widget.#{ @ctx.id }.render.children.complete"
                callback: =>
                  chunk.end @widgetRepo.getTemplateCode()
                  subscription.unsubscribe()


        # css inclide
        css: (chunk, context, bodies, params) =>
          chunk.map (chunk) =>
            subscription = postal.subscribe
              topic: "widget.#{ @ctx.id }.render.children.complete"
              callback: =>
                chunk.end @widgetRepo.getTemplateCss()
                subscription.unsubscribe()


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

              {#extend type="//RootLayout" someParam="foo"}
                {#widget type="//MainMenu" selectedItem=activeItem placeholder="default"/}
              {/extend}

          This section accepts the same params as the "widget" section, except of placeholder which logically cannot
          be used with extend.

          todo: add check of (un)existance of other root sections in the template
          ###

          chunk.map (chunk) =>

            if not params.type? or !params.type
              throw "Extend must have 'type' param defined!"

            if params.placeholder?
              console.log "WARNING: 'placeholder' param is useless for 'extend' section"

            require [
              "cord-w!#{ params.type }@#{ @getBundle() }"
              "cord!widgetCompiler"
            ], (WidgetClass, widgetCompiler) =>

              widget = new WidgetClass @compileMode

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
          chunk.map (chunk) =>
            require [
              "cord-w!#{ params.type }@#{ @getBundle() }"
              'cord!widgetCompiler'
            ], (WidgetClass, widgetCompiler) =>

              widget = new WidgetClass
                compileMode: true

              emptyBodyRe = /^function body_[0-9]+\(chk,ctx\)\{return chk;\}$/ # todo: move to static
              if context.surroundingWidget?
                ph = params.placeholder ? 'default'
                sw = context.surroundingWidget

                timeoutTemplateName = null
                if bodies.timeout?
                  @_timeoutBlockCounter ?= 0

                  timeoutTemplateName = "__timeout_#{ @_timeoutBlockCounter++ }.html.js"
                  tmplPath = "#{ @getDir() }/#{ timeoutTemplateName }"
                  widgetCompiler.saveBodyTemplate(bodies.timeout, @compiledSource, tmplPath)

                widgetCompiler.addPlaceholderContent sw, ph, widget, params, timeoutTemplateName

              else if bodies.block? && not emptyBodyRe.test(bodies.block.toString())
                throw "Name must be explicitly defined for the inline-widget with body placeholders (#{ @constructor.name } -> #{ widget.constructor.name })!" if not params.name? or params.name == ''
                widgetCompiler.registerWidget widget, params.name

              else
                # ???

              if bodies.block? && not emptyBodyRe.test(bodies.block.toString())
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
            ], (widgetCompiler) =>
              if bodies.block?
                # todo: check other params and output warning
                params ?= {}
                name = params.name ? 'inline' + (@inlineCounter++)
                tag = params.tag ? 'div'
                cls = params.class ? ''
                if context.surroundingWidget?
                  ph = params?.placeholder ? 'default'
                  sw = context.surroundingWidget

                  templateName = "__inline_#{ name }.html.js"
                  tmplPath = "#{ @getDir() }/#{ templateName }"
                  widgetCompiler.saveBodyTemplate(bodies.block, @compiledSource, tmplPath)

                  widgetCompiler.addPlaceholderInline sw, ph, this, templateName, name, tag, cls

                  ctx = @getBaseContext().push(@ctx)

                  tmpName = "tmp#{ _.uniqueId() }"
                  dust.register tmpName, bodies.block

                  dust.render tmpName, ctx, (err, out) =>
                    if err then throw err
                    chunk.end ""

                else
                  throw "inlines are not allowed outside surrounding widget [#{ @constructor.name }(#{ @ctx.id })]"
              else
                console.log "Warning: empty inline in widget #{ @constructor.name }(#{ @ctx.id })"

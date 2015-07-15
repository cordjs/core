# need to set it here because compiler is run without cordjs initialization scripts
global.CORD_IS_BROWSER = false
global.CORD_PROFILER_ENABLED = false

define [
  'cord!utils/Future'
  'underscore'
  'dustjs-helpers'
  'pathUtils'
  'fs'
  'path'
], (Future, _, dust, pathUtils, fs, path) ->

  dustPartialsPreventionCallback = (tmplPath, callback) ->
    ###
    Special callback for dust.onLoad to prevent loading of partials during widget compilation
    ###
    dust.cache[tmplPath] = ''
    callback null, ''

  bodyRe = /(body_[0-9]+)/g
  emptyBodyRe = /^function body_[0-9]+\(chk,ctx\)\{return chk;\}$/

  class WidgetCompiler

    widget: null
    inlineCounter: 0
    compiledSource: null

    _baseContext: null

    _timeoutBlockCounter: 0
    _deferredBlockCounter: 0

    _ownerUid: null
    _extend: null
    _widgets: null
    _widgetsByName: null

    _extendPhaseFinished: false


    @compileWidgetTemplate: (widgetPath, tmplSourcePath) ->
      ###
      Convenient endpoint to run widget's template compilation.
      @param String widgetPath canonical widget path
      @param String tmplSourcePath path to the source template file (.html)
      @return Future[Nothing]
      ###
      Future.require("cord-w!#{ widgetPath }").then (WidgetClass) ->
        compiler = new WidgetCompiler(WidgetClass)
        compiler.compileTemplate(tmplSourcePath)


    constructor: (WidgetClass) ->
      @widget = new WidgetClass(compileMode: true)

      @_widgets = {}
      @_widgetsByName = {}
      @_ownerUid = @registerWidget(@widget).uid

      # Preventing loading of partials during widget compilation
      dust.onLoad = dustPartialsPreventionCallback


    compileTemplate: (tmplSourcePath) ->
      ###
      Compiles given template file for the owner widget.
      @param String tmplSourcePath path to the source template file (.html)
      @return {Future<undefined>}
      ###
      parts = tmplSourcePath.split('/')
      fileName = parts.pop()
      lastDirName = parts[parts.length - 1]
      ext = path.extname(fileName)
      fileWithoutExt = fileName.slice(0, -ext.length)

      isMainTemplate = lastDirName == fileWithoutExt

      tmplPath = @widget.getPath()

      # Determine if we compile main widget template (with the same name) or additional one.
      # For an additional template other dustjs name used and structure file is not needed
      if isMainTemplate
        tmplFullPath = "./#{ pathUtils.getPublicPrefix() }/bundles/#{ @widget.getTemplateFilePath() }"
      else
        tmplFullPath = "./#{ pathUtils.getPublicPrefix() }/bundles/#{ @widget.getDir() }/#{ fileName }"
        tmplPath = "cord!/#{ @widget.getDir() }/#{ fileWithoutExt }"

      Future.call(fs.readFile, tmplSourcePath, 'utf8').then (htmlString) =>
        @compiledSource = dust.compile(htmlString, tmplPath)
        amdSource = "define(['dustjs-helpers'], function(dust){#{ @compiledSource }});"
        tmplPromise = Future.call(fs.writeFile, "#{ tmplFullPath }.js", amdSource)

        structPromise =
          if isMainTemplate
            if @widget.getPath() != '/cord/core//Switcher'
              dust.loadSource(@compiledSource)
              Future.call(dust.render, tmplPath, @getBaseContext().push(@widget.ctx)).then =>
                Future.call(fs.writeFile, "#{ tmplFullPath }.struct.js", @getStructureCode(false, true))
            else
              Future.call(fs.writeFile, "#{ tmplFullPath }.struct.js", 'define([],function(){return {};});')
          else
            Future.resolved()

        Future.all [tmplPromise, structPromise]
      .then ->
        return


    registerWidget: (widget, name, timeout, timeoutTemplateName) ->
      if not @_widgets[widget.ctx.id]?
        wdt =
          uid: widget.ctx.id
          path: widget.getPath()
          placeholders: {}
        if name?
          wdt.name = name
          @_widgetsByName[name] = wdt.uid
        if timeout?
          wdt.timeout = parseInt(timeout)
          wdt.timeoutTemplate = timeoutTemplateName if timeoutTemplateName?
        @_widgets[widget.ctx.id] = wdt
      @_widgets[widget.ctx.id]


    addExtendCall: (widget, params) ->
      if @_extendPhaseFinished
        throw "'#extend' appeared in wrong place (extending widget #{ widget.constructor.name })!"
      if @_extend?
        throw "Only one '#extend' is allowed per template (#{ widget.constructor.name })!"

      widgetRef = @registerWidget widget, params.name

      cleanParams = _.clone params
      delete cleanParams.type
      delete cleanParams.name

      @_extend =
        widget: widgetRef.uid
        params: cleanParams
      @_extend.name = params.name if params.name


    addPlaceholderContent: (surroundingWidget, placeholderName, widget, params, timeoutTemplateName) ->
      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget, params.name

      swRef.placeholders[placeholderName] ?= []

      cleanParams = _.clone params
      delete cleanParams.type
      delete cleanParams.placeholder
      delete cleanParams.name
      delete cleanParams.class
      delete cleanParams.timeout

      info =
        widget: widgetRef.uid
        params: cleanParams
      info.class = params.class if params.class
      info.name = params.name if params.name
      info.timeout = parseInt(params.timeout) if params.timeout
      info.timeoutTemplate = timeoutTemplateName if timeoutTemplateName?

      swRef.placeholders[placeholderName].push info



    addPlaceholderInline: (surroundingWidget, placeholderName, widget, templateName, name, tag, cls) ->
      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderName] ?= []
      swRef.placeholders[placeholderName].push
        inline: widgetRef.uid
        template: templateName
        name: name
        tag: tag
        class: cls


    _addPlaceholderPlaceholder: (surroundingWidget, placeholderName, widget, name, cls) ->
      ###
      Adds placeholder definition to the structure template
      @param Widget surroundingWidget widget inside which the #placeholder block occurs
      @param String placeholderName name of the placeholder of the surroundingWidget which is proxied
      @param Widget widget owner of the rendering template (owner-widget of this placeholder)
      @param String name name of the placeholder
      @param String cls class-string to add to the placeholder root-tag
      ###
      @extendPhaseFinished = true

      swRef = @registerWidget(surroundingWidget)
      widgetRef = @registerWidget(widget)

      swRef.placeholders[placeholderName] ?= []
      swRef.placeholders[placeholderName].push
        placeholder: widgetRef.uid
        name: name
        class: cls


    getStructureCode: (compact = true, amd = false) ->
      if @_widgets? and Object.keys(@_widgets).length > 1
        res =
          ownerWidget: @_ownerUid
          extend: @_extend
          widgets: @_widgets
          widgetsByName: @_widgetsByName
      else
        res = {}
      json = if compact
        JSON.stringify(res)
      else
        JSON.stringify(res, null, 2)
      if amd
        "define([],function(){return #{json};});"
      else
        json


    printStructure: ->
      _console.log @getStructureCode(false)


    extractBodiesAsStringList: (compiledSource) ->
      ###
      Divides full compiled source of the template into substrings of individual body function strings
      This function is needed while composing inline's sub-template file

      @return Object(String, String) key-value pairs of function names and corresponding function definition string
      ###
      startIdx = compiledSource.indexOf 'function body_0(chk,ctx){return chk'
      endIdx = compiledSource.lastIndexOf 'return body_0;})();'
      bodiesPart = compiledSource.substr startIdx, endIdx - startIdx
      result = {}
      startIdx = 0
      bodyId = 0
      while startIdx != -1
        endIdx = bodiesPart.indexOf "function body_#{ bodyId + 1 }(chk,ctx){return chk"
        len = if endIdx == -1 then compiledSource.length else endIdx - startIdx
        result['body_'+bodyId] = bodiesPart.substr startIdx, len
        bodyId++
        startIdx = endIdx
      result


    _saveBodyTemplate: (bodyFn, compiledSource, tmplPath) ->
      bodyStringList = null
      collectBodies = (name, bodyString, bodies = {}) =>
        bodies[name] = bodyString
        matchBodies = bodyString.match(bodyRe)
        for depName in matchBodies
          if not bodies[depName]?
            bodies[depName] = bodyStringList[depName]
            collectBodies depName, bodyStringList[depName], bodies
        bodies

      # todo: detect bundles or vendor dir correctly
      tmplFullPath = "./#{ pathUtils.getPublicPrefix() }/bundles/#{ tmplPath }.js"

      bodyFnName = bodyFn.name # todo: ie10 incompatible, but this is compiler and it will run only on node
      bodyStringList = @extractBodiesAsStringList(compiledSource)
      bodyList = collectBodies bodyFnName, bodyFn.toString()

      tmplString = "(function(){dust.register(\"#{ tmplPath }\", #{ bodyFnName }); " \
                 + "#{ _.values(bodyList).join '' }; return #{ bodyFnName };})();"

      amdTmplString = "define(['dustjs-helpers'], function(dust){#{ tmplString }});"
      Future.call(fs.writeFile, tmplFullPath, amdTmplString)


    _saveSubTemplate: (bodyFn, fileName) ->
      ###
      DRY code to give the sub-template full path and save it
      @param Function bodyFn dust block function to save
      @param String fileName basename of the template file without extension
      @return Future
      ###
      tmplPath = "#{ @widget.getDir() }/#{ fileName }.html"
      @_saveBodyTemplate(bodyFn, @compiledSource, tmplPath)


    _renderBodyBlock: (bodyFn, surroundingWidget) ->
      ###
      DRY for rendering sub-template body block
      @param Function bodyFn dust block function to save
      @param (optional)Widget surroundingWidget optional surrounding widget to inject into context if needed
      @param Future[String] rendered template string
      ###
      tmpName = 'tmp' + _.uniqueId()
      dust.register(tmpName, bodyFn)
      ctx = @getBaseContext().push(@widget.ctx)
      ctx.surroundingWidget = surroundingWidget if surroundingWidget
      Future.call(dust.render, tmpName, ctx)


    getBaseContext: ->
      @_baseContext ? (@_baseContext = @_buildBaseContext())


    _buildBaseContext: ->
      ###
      Creates base context for dust templates with widget plugins for compilation mode
      ###
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
            throw new Error("Extend must have 'type' param defined!") if not params.type
            console.warn "WARNING: 'placeholder' param is useless for 'extend' section" if params.placeholder?

            require ["cord-w!#{ params.type }@#{ @widget.getBundle() }"], (WidgetClass) =>

              widget = new WidgetClass(compileMode: true)

              @addExtendCall(widget, params)

              if bodies.block?
                @_renderBodyBlock(bodies.block, widget).done ->
                  chunk.end('')
                  return
                .failAloud("WidgetCompiler::#extend:#{@widget.debug()}:#{params.type}")
              else
                console.warn "WARNING: Extending layout #{ params.type } with nothing!"
                chunk.end('')


        widget: (chunk, context, bodies, params) =>
          ###
          {#widget/} block (compile mode)
          ###
          if params.type.substr(0, 2) == './'
            params.type = "//#{@widget.constructor.relativeDir}#{params.type.substr(1)}"

          chunk.map (chunk) =>
            Future.require("cord-w!#{ params.type }@#{ @widget.getBundle() }").then (WidgetClass) =>
              widget = new WidgetClass(compileMode: true)

              if bodies.timeout? and params.timeout? and params.timeout >= 0
                timeoutTemplateName = "__timeout_#{ @_timeoutBlockCounter++ }"
                timeoutTemplatePromise = @_saveSubTemplate(bodies.timeout, timeoutTemplateName)
              else
                timeoutTemplateName = null
                timeoutTemplatePromise = Future.resolved()

              hasNonEmptyBody = (bodies.block and not emptyBodyRe.test(bodies.block.toString()))

              if context.surroundingWidget?
                ph = params.placeholder ? 'default'
                sw = context.surroundingWidget

                @addPlaceholderContent sw, ph, widget, params, timeoutTemplateName

              else if hasNonEmptyBody or
                      (bodies.timeout? and params.timeout? and params.timeout >= 0)
                if not params.name? or params.name.trim() == ''
                  throw new Error(
                    'Name must be explicitly defined for the inline-widget with body placeholders or timeout block ' +
                    "(#{ @widget.constructor.name } -> #{ widget.constructor.name })!"
                  )
                @registerWidget widget, params.name.trim(), params.timeout, timeoutTemplateName


              if hasNonEmptyBody
                Future.all [
                  @_renderBodyBlock(bodies.block, widget)
                  timeoutTemplatePromise
                ]
              else
                timeoutTemplatePromise
            .then ->
              chunk.end('')
              return
            .failAloud("WidgetCompiler::#widget:#{@widget.debug()}:#{params.type}")


        inline: (chunk, context, bodies, params) =>
          ###
          {#inline/} - block of sub-template to place into surrounding widget's placeholder
          ###
          if bodies.block?
            # todo: check other params and output warning
            if context.surroundingWidget?
              params ?= {}
              name = params.name ? 'inline' + (@inlineCounter++)
              tag = params.tag ? 'div'
              cls = params.class ? ''
              chunk.map (chunk) =>
                ph = params?.placeholder ? 'default'
                sw = context.surroundingWidget

                templateName = "__inline_#{ name }"
                templateSavePromise = @_saveSubTemplate(bodies.block, templateName)

                @addPlaceholderInline sw, ph, @widget, templateName, name, tag, cls

                Future.all [
                  @_renderBodyBlock(bodies.block)
                  templateSavePromise
                ]
                .then ->
                  chunk.end('')
                  return
                .failAloud("WidgetCompiler::#inline:#{@widget.debug()}")

            else
              throw new Error(
                "Inlines are not allowed outside surrounding widget [#{ @widget.constructor.name }(#{ @widget.ctx.id })]"
              )
          else
            console.warn "WARNING: empty inline in widget #{ @widget.constructor.name }(#{ @widget.ctx.id })"


        placeholder: (chunk, context, bodies, params) =>
          ###
          {#placeholder/} - placeholder inside placeholder (proxy)
          ###
          if context.surroundingWidget?
            params ?= {}
            if params.bypass?
              if params.name?
                throw new Error("'bypass' and 'name' params couldn't be used together for placeholder")
              if params.placeholder?
                throw new Error("'bypass' and 'placeholder' params couldn't be used together for placeholder")
              name = params.bypass
              ph = params.bypass
            else
              name = params.name ? 'default'
              ph   = params.placeholder ? 'default'
            cls  = params.class ? ''
            @_addPlaceholderPlaceholder(context.surroundingWidget, ph, @widget, name, cls)
          #else
          # placeholders inside HTML-markup are not interesting here


        deferred: (chunk, context, bodies) =>
          ###
          {#deferred/} - block depended on deferred context values, need to be saved in separate sub-template
          ###
          if bodies.block?
            # identification of the template is performed by the order of appearance of the deferred blocks
            # it's a little bit wonky but have no other good choice
            deferredId = @_deferredBlockCounter++
            chunk.map (chunk) =>
              Future.all [
                @_saveSubTemplate(bodies.block, "__deferred_#{ deferredId }")
                @_renderBodyBlock(bodies.block)
              ]
              .then ->
                chunk.end('')
                return
              .failAloud("WidgetCompiler::#deferred:#{@widget.debug()}")
          else
            console.warn "WARNING: empty deferred block in widget #{ @widget.constructor.name }(#{ @widget.ctx.id })"

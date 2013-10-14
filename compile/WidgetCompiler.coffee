define [
  'cord!utils/Future'
  'underscore'
  'dustjs-helpers'
  'pathUtils'
  'fs'
], (Future, _, dust, pathUtils, fs) ->

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
      Future.require("cord-w!#{ widgetPath }").flatMap (WidgetClass) ->
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
      @return Future[Nothing]
      ###
      tmplPath = @widget.getPath()
      tmplFullPath = "./#{ pathUtils.getPublicPrefix() }/bundles/#{ @widget.getTemplatePath() }"
      Future.call(fs.readFile, tmplSourcePath, 'utf8').flatMap (htmlString) =>
        @compiledSource = dust.compile(htmlString, tmplPath)
        tmplFuture = Future.call(fs.writeFile, "#{ tmplFullPath }.js", @compiledSource)

        structFuture =
          if @widget.getPath() != '/cord/core//Switcher'
            dust.loadSource(@compiledSource)
            Future.call(dust.render, tmplPath, @getBaseContext().push(@widget.ctx)).flatMap =>
              Future.call(fs.writeFile, "#{ tmplFullPath }.struct.json", @getStructureCode(false))
          else
            Future.call(fs.writeFile, "#{ tmplFullPath }.struct.json", '{}')

        tmplFuture.zip(structFuture)


    registerWidget: (widget, name) ->
      if not @_widgets[widget.ctx.id]?
        wdt =
          uid: widget.ctx.id
          path: widget.getPath()
          placeholders: {}
        if name?
          wdt.name = name
          @_widgetsByName[name] = wdt.uid
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


    getStructureCode: (compact = true) ->
      if @_widgets? and Object.keys(@_widgets).length > 1
        res =
          ownerWidget: @_ownerUid
          extend: @_extend
          widgets: @_widgets
          widgetsByName: @_widgetsByName
      else
        res = {}
      if compact
        JSON.stringify(res)
      else
        JSON.stringify(res, null, 2)


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
      tmplFullPath = "./#{ pathUtils.getPublicPrefix() }/bundles/#{ tmplPath }"

      bodyFnName = bodyFn.name # todo: ie10 incompatible
      bodyStringList = @extractBodiesAsStringList compiledSource
      bodyList = collectBodies bodyFnName, bodyFn.toString()

      tmplString = "(function(){dust.register(\"#{ tmplPath }\", #{ bodyFnName }); " \
                 + "#{ _.values(bodyList).join '' }; return #{ bodyFnName };})();"

      Future.call(fs.writeFile, tmplFullPath, tmplString).failAloud()


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

            if not params.type? or !params.type
              throw "Extend must have 'type' param defined!"

            if params.placeholder?
              _console.warn "WARNING: 'placeholder' param is useless for 'extend' section"

            require [
              "cord-w!#{ params.type }@#{ @widget.getBundle() }"
            ], (WidgetClass) =>

              widget = new WidgetClass(compileMode: true)

              @addExtendCall(widget, params)

              if bodies.block?
                ctx = @getBaseContext().push(@widget.ctx)
                ctx.surroundingWidget = widget

                tmpName = "tmp#{ _.uniqueId() }"
                dust.register tmpName, bodies.block
                dust.render tmpName, ctx, (err) =>
                  if err then throw err
                  chunk.end('')
              else
                _console.warn "WARNING: Extending widget #{ params.type } with nothing!"
                chunk.end('')


        widget: (chunk, context, bodies, params) =>
          ###
          {#widget/} block (compile mode)
          ###
          chunk.map (chunk) =>
            require ["cord-w!#{ params.type }@#{ @widget.getBundle() }"], (WidgetClass) =>
              widget = new WidgetClass(compileMode: true)

              timeoutTemplateFuture = Future.resolved()

              if context.surroundingWidget?
                ph = params.placeholder ? 'default'
                sw = context.surroundingWidget

                timeoutTemplateName = null
                if bodies.timeout?
                  timeoutTemplateName = "__timeout_#{ @_timeoutBlockCounter++ }.html.js"
                  tmplPath = "#{ @widget.getDir() }/#{ timeoutTemplateName }"
                  timeoutTemplateFuture = @_saveBodyTemplate(bodies.timeout, @compiledSource, tmplPath)

                @addPlaceholderContent sw, ph, widget, params, timeoutTemplateName

              else if bodies.block? && not emptyBodyRe.test(bodies.block.toString())
                if not params.name? or params.name == ''
                  throw "Name must be explicitly defined for the inline-widget with body placeholders " +
                    "(#{ @constructor.name } -> #{ widget.constructor.name })!"
                @registerWidget widget, params.name

              else
                # ???

              if bodies.block? && not emptyBodyRe.test(bodies.block.toString())
                ctx = @getBaseContext().push(@widget.ctx)
                ctx.surroundingWidget = widget

                tmpName = "tmp#{ _.uniqueId() }"
                dust.register tmpName, bodies.block
                Future.call(dust.render, tmpName, ctx).zip(timeoutTemplateFuture).failAloud().done ->
                  chunk.end('')
              else
                timeoutTemplateFuture.failAloud().done ->
                  chunk.end('')


        inline: (chunk, context, bodies, params) =>
          ###
          {#inline/} - block of sub-template to place into surrounding widget's placeholder
          ###
          chunk.map (chunk) =>
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
                tmplPath = "#{ @widget.getDir() }/#{ templateName }"
                templateSaveFuture = @_saveBodyTemplate(bodies.block, @compiledSource, tmplPath)

                @addPlaceholderInline sw, ph, @widget, templateName, name, tag, cls

                tmpName = "tmp#{ _.uniqueId() }"
                dust.register tmpName, bodies.block

                ctx = @getBaseContext().push(@widget.ctx)
                Future.call(dust.render, tmpName, ctx).zip(templateSaveFuture).failAloud().done ->
                  chunk.end('')

              else
                throw "inlines are not allowed outside surrounding widget [#{ @constructor.name }(#{ @ctx.id })]"
            else
              _console.warn "Warning: empty inline in widget #{ @constructor.name }(#{ @ctx.id })"

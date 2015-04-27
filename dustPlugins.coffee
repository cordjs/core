define [
  'cord!helpers/TimeoutStubHelper'
  'cord!utils/DomInfo'
  'cord!utils/Future'
  'cord!errors'
  'underscore'
], (TimeoutStubHelper, DomInfo, Future, errors, _) ->

  ###
  Set of dustjs plugin functions supporting CordJS templates special setup and structuring
  ###

  widget: (chunk, context, bodies, params) ->
    ###
    {#widget/} block handling
    ###
    tmplWidget = context.get('_ownerWidget')
    tmplWidget.childWidgetAdd(params.type)

    if params.type.substr(0, 2) == './'
      params.type = "//#{tmplWidget.constructor.relativeDir}#{params.type.substr(1)}"

    contextDomInfo = tmplWidget._domInfo

    chunk.map (chunk) ->
      normalizedName = if params.name then params.name.trim() else undefined
      normalizedName = undefined  if not normalizedName

      timeout = if params.timeout? then parseInt(params.timeout) else -1
      hasTimeout = CORD_IS_BROWSER and timeout >= 0
      timeoutDomInfo = if hasTimeout then new DomInfo(tmplWidget.debug('#widget::timeout')) else contextDomInfo

      tmplWidget.getStructTemplate().then (tmpl) ->
        # creating widget from the structured template or not depending on it's existence and name
        # btw getting and pushing futher timeout template name from the structure template if there is one
        if tmpl.isEmpty() or not normalizedName
          tmplWidget.widgetRepo.createWidget(params.type, tmplWidget, normalizedName, tmplWidget.getBundle())
        else if normalizedName
          tmpl.getWidgetByName(normalizedName).then (widget) ->
            [widget, tmpl.getWidgetInfoByName(normalizedName).timeoutTemplate]
          .catch ->
            tmplWidget.widgetRepo.createWidget(params.type, tmplWidget, normalizedName, tmplWidget.getBundle())
        # else impossible

      .then (widget, timeoutTemplate) ->
        complete = false

        tmplWidget.resolveParamRefs(widget, params).then (resolvedParams) ->
          widget.setModifierClass(params.class)
          widget.show(resolvedParams, timeoutDomInfo)
        .then (out) ->
          if not complete
            complete = true
            timeoutDomInfo.completeWith(contextDomInfo) if hasTimeout
            tmplWidget.childWidgetComplete(params.type)
            chunk.end(widget.renderRootTag(out))
          else
            TimeoutStubHelper.replaceStub(out, widget, contextDomInfo).then ($newRoot) ->
              timeoutDomInfo.setDomRoot($newRoot)
              timeoutDomInfo.domInserted().when(contextDomInfo.domInserted())
              return
            .catchIf (err) ->
              err instanceof errors.WidgetDropped or err instanceof errors.WidgetSentenced
        .catch (err) ->
          if not complete
            complete = true
            tmplWidget.childWidgetFailed(params.type, err)
          throw err
        .catch (err) ->
          chunk.setError(err)
          return

        if hasTimeout
          setTimeout ->
            # if the widget has not been rendered within given timeout, render stub template from the {:timeout} block
            if not complete
              complete = true
              widget._delayedRender = true
              TimeoutStubHelper.getTimeoutHtml(tmplWidget, timeoutTemplate, widget).then (out) ->
                tmplWidget.childWidgetComplete(params.type)
                chunk.end(widget.renderRootTag(out))
              .catch (err) ->
                tmplWidget.childWidgetFailed(params.type, err)
                throw err
              .catch (err) ->
                chunk.setError(err)
                return
          , timeout
      .catch (err) ->
        tmplWidget.childWidgetFailed(params.type, err)
        throw err
      .catch (err) ->
        chunk.setError(err)
        return


  deferred: (chunk, context, bodies, params) ->
    ###
    {#deferred/} block handling
    ###
    type = _.uniqueId('deferred_')
    if bodies.block?
      tmplWidget = context.get('_ownerWidget')
      deferredId = tmplWidget._deferredBlockCounter++
      deferredKeys = params.params.split(/[, ]/)
      needToWait = (name for name in deferredKeys when tmplWidget.ctx.isDeferred(name))

      promise = new Future(tmplWidget.debug('deferred'))
      for name in needToWait
        promise.when(tmplWidget.ctx.getPromise(name))

      tmplWidget.childWidgetAdd(type)
      chunk.map (chunk) ->
        promise.then ->
          TimeoutStubHelper.renderTemplateFile(tmplWidget, "__deferred_#{deferredId}")
        .then (out) ->
          tmplWidget.childWidgetComplete(type)
          chunk.end(out)
        .catch (err) ->
          tmplWidget.childWidgetFailed(type, err)
          throw err
        .catch (err) ->
          _console.error "Error on widget #{ tmplWidget.debug() } #deferred rendering:", err
          chunk.setError(err)
          return
    else
      ''


  placeholder: (chunk, context, bodies, params) ->
    ###
    {#placeholder/} block handling
    Placeholder - point of extension of the widget.
    ###
    tmplWidget = context.get('_ownerWidget')
    type = _.uniqueId('placeholder_')
    tmplWidget.childWidgetAdd(type)
    chunk.map (chunk) ->
      name = params?.name ? 'default'
      if params and params.class
        tmplWidget._placeholdersClasses[name] = params.class

      tmplWidget._renderPlaceholder(name, tmplWidget._domInfo).then (out) ->
        tmplWidget.childWidgetComplete(type)
        chunk.end(tmplWidget.renderPlaceholderTag(name, out))
      .catch (err) ->
        tmplWidget.childWidgetFailed(type, err)
        throw err
      .catch (err) ->
        chunk.setError(err)
        return


  i18n: (chunk, context, bodies, params) ->
    ###
    {#i18n text="" [context=""] [wrapped="true"] /}
    ###
    tmplWidget = context.get('_ownerWidget')

    text = params.text or ''
    delete(params.text)

    if tmplWidget.ctx.i18nHelper
      chunk.write(tmplWidget.ctx.i18nHelper(text, params))
    else
      chunk.write(text)


  url: (chunk, context, bodies, params) ->
    ###
    {#url routeId="" [param1=""...] /}
    ###
    tmplWidget = context.get('_ownerWidget')
    routeId = params.routeId
    if not routeId
      throw new Error tmplWidget.debug("RouteId is require for #url")
    delete(params.routeId)
    chunk.write(tmplWidget.router.urlTo(routeId, params))


  widgetInitializer: (chunk, context) ->
    ###
    Widget initialization script generator.
    Should be inserted to the bottom of the body-tag in the top-most layout widget.
    ###
    tmplWidget = context.get('_ownerWidget')

    if tmplWidget.widgetRepo._initEnd
      ''
    else
      chunk.map (chunk) ->
        tmplWidget._childWidgetCompletePromise.then ->
          chunk.end(tmplWidget.widgetRepo.getTemplateCode())
        .catch (error) ->
          chunk.setError(error)
          return


  css: (chunk, context) ->
    ###
    Inserts css-link tags for the required css-files of the widgets during server-side page generation.
    ###
    tmplWidget = context.get('_ownerWidget')
    chunk.map (chunk) ->
      tmplWidget._childWidgetCompletePromise.then ->
        tmplWidget.widgetRepo.getTemplateCss()
      .then (html) ->
        chunk.end(html)
      .catch (error) ->
        chunk.setError(error)
        return

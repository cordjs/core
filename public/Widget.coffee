`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'underscore'
  './widgetInitializer'
  'dustjs-linkedin'
  './dustLoader'
  'postal'
], (_, widgetInitializer, dust, dustLoader, postal) ->

  class Widget

    # widget context
    ctx: null

    # child widgets
    children: null
    childByName: null

    path: null

    behaviourClass: null

    getPath: ->
      if @path?
        "#{ @path }#{ @constructor.name }"
      else
        throw "path is not defined for widget #{@constructor.name}"


    constructor: (id) ->
      @children = []
      @childByName = {}
      @childBindings = {}
      @ctx = new Context(id ? 'widget' + _.uniqueId())


    loadContext: (ctx) ->
      @ctx = new Context(ctx)

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
      "/#{ @path }#{ className.charAt(0).toUpperCase() + className.slice(1) }.html"

    renderTemplate: (callback) ->
      tmplPath = @getTemplatePath()
      console.log "renderTemplate #{ tmplPath }"
      if dust.cache[tmplPath]?
        dust.render tmplPath, @getBaseContext().push(@ctx), callback
      else
        dustLoader.loadTemplate tmplPath, tmplPath, =>
          @renderTemplate callback


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
        @behaviourClass = "#{ @path }#{ @constructor.name }Behaviour"

      console.log @behaviourClass

      if @behaviourClass == false
        null
      else
        @behaviourClass

    # @browser-only
    initBehaviour: ->
      behaviourClass = @getBehaviourClass()
      console.log 'initBehaviour', @constructor.name, behaviourClass
      if behaviourClass?
        console.log "require", behaviourClass
        require [behaviourClass], (BehaviourClass) =>
          console.log "loaded behaviour class #{ behaviourClass }"
          behaviour = new BehaviourClass @



    # should not be used directly, use getBaseContext() for lazy loading
    _baseContext: null

    getBaseContext: ->
      @_baseContext ? (@_baseContext = @_buildBaseContext())

    _buildBaseContext: ->
      dust.makeBase

        # widget-block
        widget: (chunk, context, bodies, params) =>
          chunk.map (chunk) =>

            WidgetClass = require "./#{ params.class }"
            widget = new WidgetClass

            @children.push widget
            @childByName[params.name] = widget if params.name?

            showCallback = ->
              console.log 'showCallback'
              widget.show params, (err, output) ->
                if err then throw err
                chunk.end "<div id=\"#{ widget.ctx.id }\">#{ output }</div>"

            waitCounter = 0
            waitCounterFinish = false

            bindings = {}

            # waiting for parent's necessary context-variables availability before rendering widget...
            for name, value of params
              if name != 'name' and name != 'class'
                if value.charAt(0) == '!'
                  value = value.slice 1
                  waitCounter++
                  bindings[value] = name
                  postal.subscribe
                    topic: "widget.#{ @ctx.id }.change.#{ value }"
                    callback: (data) ->
                      params[name] = data.value
                      waitCounter--
                      if waitCounter == 0 and waitCounterFinish
                        showCallback()

            # todo: potentially not cross-browser code!
            if Object.keys(bindings).length != 0
              @childBindings[widget.ctx.id] = bindings

            waitCounterFinish = true
            if waitCounter == 0
              showCallback()


        # widget initialization script generator
        widgetInitializer: (chunk, context, bodies, params) ->
          chunk.map (chunk) ->
            chunk.end widgetInitializer.getTemplateCode()


  class Context

    constructor: (arg) ->
      if typeof arg is 'object'
        for key, value of arg
          console.log 'initial context', key, value
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
        postal.publish "widget.#{ @id }.someChange", {}


    setSingle: (name, newValue) ->
      triggerChange = false
      if @[name]?
        oldValue = @[name]
        console.log name, oldValue, newValue
        if oldValue != newValue
          triggerChange = true
      else
        console.log 'trigger change on not exist', @, name, @centralTabGroup
        triggerChange = true

      @[name] = newValue

      if triggerChange
        console.log 'triggerChange', name, newValue
        postal.publish "widget.#{ @id }.change.#{ name }",
          name: name
          value: newValue

      triggerChange


  Widget
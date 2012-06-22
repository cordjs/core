`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'underscore'
  './widgetInitializer'
  'dustjs-linkedin'
], (_, widgetInitializer, dust) ->

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
      @ctx = {}
      @ctx.id = id ? 'widget' + _.uniqueId()


    loadContext: (ctx) ->
      @ctx = ctx

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


    getInitCode: (parentId) ->
      parentStr = if parentId? then ", '#{ parentId }'" else ''

      namedChilds = {}
      for name, widget of @childByName
        namedChilds[widget.ctx.id] = name

      """
      wi.init('#{ @getPath() }', #{ JSON.stringify @ctx }, #{ JSON.stringify namedChilds }#{ parentStr });
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

            @children.push(widget)
            @childByName[params.name] = widget if params.name?

            widget.show params, (err, output) ->
              if err then throw err
              chunk.end "<div id=\"#{ widget.ctx.id }\">#{ output }</div>"

        # widget initialization script generator
        widgetInitializer: (chunk, context, bodies, params) ->
          chunk.map (chunk) ->
            chunk.end widgetInitializer.getTemplateCode()


  Widget
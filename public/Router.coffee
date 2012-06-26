`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'url'
  './widgetInitializer'
], (url, widgetInitializer) ->

  class Router

    constructor: ->
      @routes = []

    process: (req, res) ->
      path = url.parse req.url
      console.log "router.process #{ req.url } #{ path.pathname }"

      if (route = @matchRoute path.pathname)
        rootWidgetPath = route.widget
        action = route.action
        params = route.params

        res.writeHead 200, {'Content-Type': 'text/html'}

        RootWidgetClass = require(rootWidgetPath);
        rootWidget = new RootWidgetClass;
        widgetInitializer.setRootWidget rootWidget

        rootWidget.showAction action, params, (err, output) ->
          if err then throw err
          res.end output

        true
      else
        false


    addRoutes: (routes) ->
      for path, definition of routes
        @routes.push(new Route(path, definition))

    matchRoute: (path, options) ->
      for route in @routes
        if route.match(path, options)
          return route

#    @add: (path, callback) ->
#      if (typeof path is 'object' and path not instanceof RegExp)
#        @add(key, value) for key, value of path
#      else
#        @routes.push(new @(path, callback))


  namedParam = /:([\w\d]+)/g
  splatParam = /\*([\w\d]+)/g
  escapeRegExp = /[-[\]{}()+?.,\\^$|#\s]/g

  class Route

    constructor: (@path, @definition) ->
      @widget = @definition.widget ? null
      @action = @definition.action ? 'default'
      @params = @definition.params ? {}

      @names = []

      if typeof path is 'string'
        namedParam.lastIndex = 0
        while (match = namedParam.exec(path)) != null
          @names.push(match[1])

        splatParam.lastIndex = 0
        while (match = splatParam.exec(path)) != null
          @names.push(match[1])

        path = path.replace(escapeRegExp, '\\$&')
                   .replace(namedParam, '([^\/]*)')
                   .replace(splatParam, '(.*?)')

        @route = new RegExp('^' + path + '$')
      else
        @route = path

    match: (path, options = {}) ->
      match = @route.exec(path)
      return false unless match
      options.match = match
      params = match.slice(1)

      if @names.length
        for param, i in params
          options[@names[i]] = param

      @params = options
      true
#      @callback.call(null, options) isnt false


  Router
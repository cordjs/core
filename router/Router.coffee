define ['underscore'], (_) ->

  class Router

    _currentPath: ''


    constructor: ->
      @routes = []
      @fallbackRoutes = []


    addRoutes: (routes) ->
      ###
      Registers array of routes.
      @param Map[path -> definition] routes map of route definitions
      ###
      for path, definition of routes
        @routes.push(new Route(path, definition))


    addFallbackRoutes: (routes) ->
      ###
      Registers array of fallback routes if no other routes found.
      @param Map[path -> definition] routes map of route definitions
      ###
      for path, definition of routes
        @fallbackRoutes.push(new Route(path, definition, true))


    matchRoute: (path) ->
      ###
      Finds the first matching route for the given path between registered routes.
      @param String path
      @return Object|boolean found route and extracted params
                             false if route is not found
      ###

      for route in @routes
        if (params = route.match(path))
          return {
            route: route
            params: params
          }

      # if no normal route found, try to match any of fallback route
      @matchFallbackRoute path


    matchFallbackRoute: (path) ->
      ###
      Finds the first matching route for the given path between registered fallback routes.
      @param String path
      @return Object|boolean found route and extracted params
                             false if route is not found
      ###
      for route in @fallbackRoutes
        if (params = route.match(path))
          return {
            route: route
            params: params
          }

      false


    getCurrentPath: ->
      ###
      @return String
      ###
      @_currentPath



  namedParam = /:([\w\d]+)/g
  splatParam = /\*([\w\d]+)/g
  escapeRegExp = /[-[\]{}()+?.,\\^$|#\s]/g



  class Route
    ###
    Individual route definition.
    ###

    constructor: (@path, definition, fallback = false) ->
      throw new Error("Required 'widget' or 'callback' options is not set in route '#{ path }' definition!") if definition.widget? and definition.callback?
      @widget = definition.widget
      @callback = definition.callback if definition.callback?

      @params = definition.params ? {}

      path = new RegExp(path) if definition.regexp

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


        if path.charAt(path.length - 1) == '/'
          path += '?'

        @route = new RegExp('^' + path + if not fallback then '$' else '')
      else
        @route = path


    match: (path) ->
      ###
      Matches the route with the given path
      @param String path
      @return Object|false key-value with the resulting params if the path matches or false otherwise
      ###
      match = @route.exec(path)
      return false unless match
      params = {}

      if @names.length
        for param, i in match.slice(1)
          params[@names[i]] = param

      _.extend params, @params



  Router

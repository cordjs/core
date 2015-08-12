define ['underscore'], (_) ->

  class Router

    # current url. May be undefined for example for serverSideRouter
    _currentPath: undefined
    # function that is called when `requireAuth` option is enabled for the matched route
    _authCheckCallback: null


    constructor: ->
      @routes = []
      @reRoutes = {}
      @fallbackRoutes = []


    addRoutes: (routes) ->
      ###
      Registers array of routes.
      @param Map[path -> definition] routes map of route definitions
      ###
      for path, definition of routes
        route = new Route(path, definition)
        @routes.push(route)

        if definition.routeId
          if definition.shim
            for oldKey, newKey of definition.shim
              path = path.replace ':' + oldKey, ':' + newKey
          @reRoutes[definition.routeId] = path


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


    urlTo: (routeId, params = {}) ->
      if @reRoutes[routeId]
        url = @reRoutes[routeId]

        getParams = ''

        for param, value of params
          if url.indexOf(':' + param) != -1
            url = url.replace(':' + param, value)
          else if value != null and value != undefined
            getParams += "&#{encodeURIComponent(param)}=#{encodeURIComponent(value)}"

        if getParams
          if url.indexOf('?') == -1
            getParams = '?' + getParams.substr(1)
          url += getParams
        url
      else
        throw new Error "Route with id #{routeId} is undefined"


    setAuthCheckCallback: (cb) ->
      ###
      Inject authentication checking function to support `requireAuth` option.
      The callback should return Boolean or Future[Boolean]. If result is `true` then transition is performed as normal,
       otherwise - navigate call is failed and page reload is expected with login form.
      @param {Function} cb
      ###
      @_authCheckCallback = cb



  namedParam = /:([\w\d]+)/g
  splatParam = /\*([\w\d]+)/g
  escapeRegExp = /[-[\]{}()+?.,\\^$|#\s]/g



  class Route
    ###
    Individual route definition.
    ###

    # if true, router should check authentication via `authCheckCallback` before processing navigation
    requireAuth: false


    constructor: (path, definition, fallback = false) ->
      ###
      definition.mergeParams - optional Array of param names which should be merged together into key-value object and
                               assigned to param with special name `__mergedParams`. This feature is useful when
                               there is a special middleware router-widget which need to bypass params to the next level.
      ###
      throw new Error("Required 'widget' or 'callback' options is not set in route '#{ path }' definition!") if definition.widget? and definition.callback?
      @widget = definition.widget
      @callback = definition.callback if definition.callback?
      @requireAuth = !!definition.requireAuth
      @mergeParams = definition.mergeParams

      @params = definition.params ? {}

      @names = []

      if not definition.regexp
        namedParam.lastIndex = 0
        while (match = namedParam.exec(path)) != null
          @names.push(match[1])

        splatParam.lastIndex = 0
        while (match = splatParam.exec(path)) != null
          @names.push(match[1])

        path = path.replace(escapeRegExp, '\\$&')
                   .replace(namedParam, '([^\/]*)')
                   .replace(splatParam, '(.*?)')

        if path.charAt(path.length - 1) != '/'
          path += '/'
        path += '?'

        @route = new RegExp('^' + path + if not fallback then '$' else '')
      else
        namedParamInRe = /\\\:([^\/]+)/g
        namedParamInRe.lastIndex = 0
        while (match = namedParamInRe.exec(path)) != null
          @names.push(match[1])
        path = path.replace(namedParamInRe, '([^\/\?]+)')

        @route = new RegExp(path)


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

      if @mergeParams and @mergeParams.length > 0
        mergedParamValue = {}
        mergedParamValue[name] = params[name] for name in @mergeParams when params[name] != undefined
        params.__mergedParams = mergedParamValue

      _.extend params, @params



  Router

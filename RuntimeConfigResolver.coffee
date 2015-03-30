define [
  'cord!utils/Future'
  'eventemitter3'
  'lodash'
  'cord!Utils'
], (Future, EventEmitter, _, Utils) ->

  class ResolveRequest
    ###
    This class is value holder for one config to resolve
    ###

    constructor: (@name, @future, @originalConfig) ->


  class RuntimeConfigResolver extends EventEmitter
    ###
    This service used to defer other services initialization until all of required runtime parameters are resolved.
    Runtime parameters stored in cookies between requests.
    Runtime parameter placeholders present in service config, passed to the method resolveConfig(), which
    returns a Future with resolved parameters. If there was no placeholders in passed config, future returns already
    resolved with original passed config. Other services can set a parameter value by calling setParameter() method
    ###

    @inject: ['cookie']

    @cookieName = '_runtime_config_values'


    constructor: ->
      @parameters = {}
      # Resolve requests, mapped by name
      @resolveRequests = {}
      # isPending futures, mapped by name
      @isPendings = {}


    init: ->
      ###
      Init method fetch stored parameters from cookies
      ###
      @_loadParameters()


    resolveConfig: (name, config) ->
      ###
      Returns Future with resolved config. Replaces all parameters, which surrounded by % sign (i.e. %PARAM_NAME%) to
      its value. Now or in future, when all parameters will be available.
      You should provide unique name of resolve request
      ###
      if @resolveRequests[name] != undefined
        return @resolveRequests[name].future

      config = _.cloneDeep(config)
      future = Future.single("Resolve runtime config for #{name}")
      if false != resolvedConfig = @_tryResolve(config)
        future.resolve(resolvedConfig)
      else
        @resolveRequests[name] = new ResolveRequest(name, future, config)
        if not CORD_IS_BROWSER
          # We will never can set runtime parameter on server side,
          # so, we should reject this future
          future.reject(new Error('Runtime config is not available on server side!'))
      @_getIsPendingFuture(name).resolve(future.state() == 'pending')
      future.finally =>
        delete @isPendings[name]
        @_getIsPendingFuture(name).resolve(false)
        return
      future


    setParameter: (name, value) ->
      ###
      Sets a parameter's value by it's name.
      Name should be without % on edges
      ###
      @parameters[name] = value;
      @_saveParameters()

      for name, request of @resolveRequests
        if false != resolvedConfig = @_tryResolve(request.originalConfig)
          delete @resolveRequests[name]
          request.future.resolve(resolvedConfig)

      @emit('setParameter',
        name: name,
        value: value
      )


    clearParameters: ->
      ###
      This method should be called on user logout. Clears all parameters from current instance and cookies
      ###
      @parameters = {}
      @_saveParameters()


    isPending: (name) ->
      ###
      Indicates, that resolve request pending (Await for user input)
      Result is Future[Boolean]
      Keeps pending until method resolveConfig is called. Result of resolve is pending state of Resolve future,
      immediately after resolveConfig(call)
      ###
      @_getIsPendingFuture(name)


    _tryResolve: (config) ->
      ###
      Make a try to resolve config. If try is successful, method returns resolved config, else it returns false
      ###
      allResolved = true
      resolvedConfig = _.cloneDeep(config, (val) =>
        if _.isString(val)
          # Replace variables by regexp replace
          val.replace(/%%|%([^%\s]+)%/g, (matches...) =>
            if matches[1] == undefined
              # skip '%%'
              '%%'
            else
              name = matches[1]
              if @parameters[name] != undefined
                @parameters[name]
              else
                allResolved = false
                matches[0]
          )
      )
      if allResolved then resolvedConfig else false


    _getIsPendingFuture: (name) ->
      ###
      Gets or create isPending future
      ###
      @isPendings[name] = Future.single("IsPending request for #{name}") if @isPendings[name] == undefined
      @isPendings[name]


    _saveParameters: ->
      ###
      Saves parameters to cookie storage
      ###
      @cookie.set(RuntimeConfigResolver.cookieName, JSON.stringify(@parameters))


    _loadParameters: ->
      ###
      Loads parameters from cookie storage
      ###
      @parameters = try
        JSON.parse(@cookie.get(RuntimeConfigResolver.cookieName))
      catch
        {}

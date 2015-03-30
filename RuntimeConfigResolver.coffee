define [
  'cord!utils/Future'
  'eventemitter3'
  'lodash'
  'cord!Utils'
], (Future, EventEmitter, _, Utils) ->

  class ConfigToResolve
    ###
    This class is value holder for one config to resolve
    ###
    constructor: (@future, @originalConfig) ->


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
      @configsToResolve = []


    init: ->
      ###
      Init method fetch stored parameters from cookies
      ###
      @_loadParameters()


    resolveConfig: (config) ->
      ###
      Returns Future with resolved config. Replaces all parameters, which surrounded by % sign (i.e. %PARAM_NAME%) to
      its value. Now or in future, when all parameters will be available
      ###
      config = _.cloneDeep(config)
      if false != resolvedConfig = @_tryResolve(config)
        Future.resolved(resolvedConfig)
      else
        future = Future.single('resolveRuntimeConfig')
        if CORD_IS_BROWSER
          @configsToResolve.push(new ConfigToResolve(future, config))
        else
          # We will never can set runtime parameter on server side,
          # so, we should reject this future
          future.reject(new Error('Runtime config is not available on server side!'))
        future


    setParameter: (name, value) ->
      ###
      Sets a parameter's value by it's name.
      Name should be without % on edges
      ###
      @parameters[name] = value;
      @_saveParameters()

      for configToResolve in @configsToResolve
        if false != resolvedConfig = @_tryResolve(configToResolve.originalConfig)
          @configsToResolve = _.without(@configsToResolve, configToResolve)
          configToResolve.future.resolve(resolvedConfig)

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


    isPending: ->
      ###
      Indicates, that someone waits for runtime config resolving
      ###
      @configsToResolve.length > 0


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

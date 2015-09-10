define [
  'cord!errors'
  'cord!utils/Future'
  'eventemitter3'
  'lodash'
], (errors, Future, EventEmitter, _) ->

  class RuntimeConfigResolver extends EventEmitter
    ###
    This service used to resolve runtime parameter in configs. Stores parameters in cookies
    ###

    @inject: ['cookie']

    @cookieName: '_runtime_config_values'


    constructor: ->
      @parameters = {}


    init: ->
      ###
      Init method fetch stored parameters from cookies
      ###
      @_loadParameters()


    setParameter: (nameOrObject, value, emitEvent = true) ->
      ###
      Sets a parameter's value by it's name.
      Or sets parameters object value
      Name should be without % on edges
      ###
      if typeof nameOrObject == 'string'
        @parameters[nameOrObject] = value
      else if nameOrObject
        @parameters[key] = value for key, value of nameOrObject


      Future.try =>
        @_saveParameters()
      .then =>
        if emitEvent
          @emit('setParameter',
            name: nameOrObject,
            value: value
          )


    getParameter: (name, defaultValue) ->
      ###
      Gets a parameter's value by it's name.
      Name should be without % on edges
      ###
      if _.has(@parameters, name) then @parameters[name] else defaultValue


    clearParameters: ->
      ###
      This method should be called on user logout. Clears all parameters from current instance and cookies
      ###
      @parameters = {}
      @_saveParameters()


    resolveConfig: (config, parameters = {}) ->
      ###
      Make a try to resolve config. If try is successful, method returns resolved config, else it returns false
      @param config Config to resolve
      @param parameters optionally one-time used parameters.
      ###
      @resolveConfigByParams(config, _.extend({}, @parameters, parameters))


    resolveConfigByParams: (config, parameters = {}) ->
      ###
      Make a try to resolve config. If try is successful, method returns resolved config, else it returns false
      @param config Config to resolve
      @param parameters optionally one-time used parameters.
      ###
      resolvedConfig = _.cloneDeep config, (val) =>
        if _.isString(val)
          # Replace variables by regexp replace
          val.replace /%%|%([^%\s]+)%/g, (matches...) =>
            if matches[1] == undefined
              # skip '%%'
              '%%'
            else
              name = matches[1]
              if parameters[name] != undefined
                parameters[name]
              else
                throw new errors.ConfigError("Parameter #{name} is not defined")
      resolvedConfig


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

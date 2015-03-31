define [
  'cord!utils/Future'
  'eventemitter3'
  'lodash'
], (Future, EventEmitter, _) ->

  class RuntimeConfigResolver extends EventEmitter
    ###
    This service used to resolve runtime parameter in configs. Stores parameters in cookies
    ###

    @inject: ['cookie']

    @cookieName = '_runtime_config_values'


    constructor: ->
      @parameters = {}


    init: ->
      ###
      Init method fetch stored parameters from cookies
      ###
      @_loadParameters()


    setParameter: (name, value) ->
      ###
      Sets a parameter's value by it's name.
      Name should be without % on edges
      ###
      @parameters[name] = value;
      @_saveParameters()

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


    resolveConfig: (config) ->
      ###
      Make a try to resolve config. If try is successful, method returns resolved config, else it returns false
      ###
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
                throw new Error("Parameter #{name} is not defined")
          )
      )
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

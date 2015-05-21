define [
  'cord!utils/Future'
  'cord!Api'
], (Future, Api) ->

  class ApiFactory

    @inject: ['container', 'runtimeConfigResolver']


    constructor: () ->
      #Here we'll cache ready api objects
      @_cachedApi = {}


    getApiByDefaultParams: (config, params = {}) ->
      ###
      Creates an Api object with default config and params
      @params {Object|undefined} params - params to be substituted in default config instead of %param_name%
      ###
      Future.try => @runtimeConfigResolver.resolveConfig(config, params)
        .then (apiConfig) => @_processResolvedConfig(apiConfig)


    getApiByParams: (config, params = {}) ->
      ###
      Creates an Api object with config and params
      For the same config and params the same object will be returned
      @param {Object} config - Api config
      @param {Object|undefined} params - params to be substituted in config instead of %param_name%
      ###
      Future.try => @runtimeConfigResolver.resolveConfigByParams(config, params)
        .then (apiConfig) => @_processResolvedConfig(apiConfig)


    _processResolvedConfig: (apiConfig) ->
      key = JSON.stringify(apiConfig)
      if @_cachedApi[key]
        Future.resolved(@_cachedApi[key])
      else
        api = new Api(@container, apiConfig)
        @container.injectServices(api)
          .then -> api.init()
          .then -> api.configure(apiConfig)
          .then => @_cachedApi[key] = api
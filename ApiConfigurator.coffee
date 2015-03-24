define [
  'cord!Utils'
  'lodash'
], (Utils, _) ->

  class ApiConfigurator

    @inject: ['cookie', 'api']
    @cookieName = '_api_config_vars'


    constructor: (@config) ->
      @variables = {}


    init: ->
      # Load stored variables from cookies
      @variables = @cookie.get(ApiConfigurator.cookieName) ? {}
      @_applyConfig()
      @api.on('host.changed', (newHost) => @setBackendHost(newHost))


    setBackendHost: (newHost) ->
      @variables =
        '%BACKEND_HOST%': newHost
      @_applyConfig()
      @cookie.set(ApiConfigurator.cookieName, @variables)


    _applyConfig: ->
      ###
      Applies config to api service
      ###
      config = _.cloneDeep(
        @config,
        (val) => Utils.substituteTemplate(val, @variables)
      )
      @api.configure(config)


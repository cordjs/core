define [
  'cord!Utils'
  'lodash'
  'cord!Api'
  'eventemitter3'
], (Utils, _, Api, EventEmitter) ->

  class ApiConfigurator extends EventEmitter

    @inject: ['cookie', 'container']
    @cookieName = '_api_config_vars'


    constructor: (@config) ->
      @variables = {}


    init: ->
      # Initialize api service
      @api = new Api(@container, @config)
      @container.injectServices(@api)
        .then => @api.init()
        .then =>
          # Load stored variables from cookies
          @variables = try
            JSON.parse(@cookie.get(ApiConfigurator.cookieName))
          catch
            {}

          @_applyConfig()
          @api.on('host.changed', (newHost) => @setBackendHost(newHost))


    getApi: ->
      @api


    setBackendHost: (newHost) ->
      @variables =
        '%BACKEND_HOST%': newHost
      @_applyConfig()
      @cookie.set(ApiConfigurator.cookieName, JSON.stringify(@variables))
      @emit('host.changed', newHost)


    _applyConfig: ->
      ###
      Applies config to api service
      ###
      config = _.cloneDeep(
        @config,
        (val) => Utils.substituteTemplate(val, @variables)
      )
      @api.configure(config)


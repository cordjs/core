define [
  'curly'
  'cord!Utils'
  'underscore'
], (curly, Utils, _) ->

  class BrowserRequest

    constructor: (serviceContainer, options) ->
      defaultOptions =
        json: true

      @options = _.extend defaultOptions, options
      @serviceContainer = serviceContainer


    get: (url, params, callback) ->
      argssss = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      argssss.url = argssss.params.url if !argssss.url and argssss.params.url?
      argssss.callback = params.callback if !argssss.callback and argssss.params.callback?

      options =
        query: argssss.params
        json: true

      startRequest = new Date() if global.CONFIG.debug?.request
      window.curly.get argssss.url, options, (error, response, body) =>
        if global.CONFIG.debug?.request
          stopRequest = new Date()
          seconds = (stopRequest - startRequest) / 1000

          if global.CONFIG.debug?.request == 'simple'
            console.log "ServerRequest ( #{ seconds } s): #{argssss.url}"
          else
            console.log "========================================================================( #{ seconds } s)"
            console.log "ServerRequest: #{argssss.url}"
            console.log argssss.params
            console.log body if global.CONFIG.debug?.request == 'full'
            console.log "========================================================================"

        argssss.callback body if typeof argssss.callback == 'function'

define [
  'curly'
  'cord!Utils'
  'underscore'
], (curly, Utils, _) ->

  class ServerRequest

    constructor: (options) ->
      defaultOptions =
        json: true

      @options = _.extend defaultOptions, options


    get: =>
      args = Utils.parseArguments arguments,
        url: 'string'
        params: 'object'
        callback: 'function'

      args.url = args.params.url if !args.url and args.params.url?
      args.callback = params.callback if !args.callback and args.params.callback?

      @options.query = args.params

      startRequest = new Date() if global.CONFIG.debug.request
      curly.get args.url, @options, (error, response, body) ->

        if global.CONFIG.debug.request
          stopRequest = new Date()
          seconds = (stopRequest - startRequest) / 1000

          if global.CONFIG.debug.request == 'simple'
            console.log "ServerRequest ( #{ seconds } s): #{args.url}"
          else
            console.log "========================================================================( #{ seconds } s)"
            console.log "ServerRequest: #{args.url}"
            console.log args.params
            console.log body if global.CONFIG.debug.request == 'full'
            console.log "========================================================================"

        args.callback body if typeof args.callback == 'function'

`if (typeof define !== 'function') { define = require('amdefine')(module) }`

fs            = require 'fs'
path          = require 'path'
requirejs     = require 'requirejs'

http          = require 'http'
serverStatic  = require 'node-static'
EventEmitter  = require('events').EventEmitter

pathDir = fs.realpathSync('.')

exports.services = services =
  nodeServer: null
  fileServer: null
  router: null

# Defaulting to standard console.
# Using javascript here to change global variable.
`_console = console`


exports.init = (baseUrl = 'public', configName = 'default', serverPort) ->
  requirejs.config
    paths: require('./requirejs/pathConfig')
    baseUrl: baseUrl
    nodeRequire: require

  requirejs [
    'pathUtils'
    'cord!AppConfigLoader'
    'cord!Console'
    'cord!Rest'
    'cord!request/xdrProxy'
    'cord!requirejs/statCollector'
    'cord!router/serverSideRouter'
    'cord!utils/Future'
    'underscore'
  ], (pathUtils, AppConfigLoader, _console, Rest, xdrProxy, statCollector, router, Future, _) ->
    pathUtils.setPublicPrefix(baseUrl)

    router.EventEmitter = EventEmitter
    services.router = router
    services.fileServer = new serverStatic.Server(baseUrl)
    services.xdrProxy = xdrProxy
    services.statCollector = statCollector

    # Loading configuration
    try
      if configName.charAt(0) != '/'
        configName = pathDir + '/conf/' + configName + '.js'
      services.config = require configName
      timeLog "Loaded config from " + configName
    catch e
      services.config = {}
      timeLog "Fail loading config from " + configName + " with error " + e

    # Merge node and browser configuration with common (defaults)
    common = _.clone services.config.common
    services.config.node = _.extend common, services.config.node

    common = _.clone services.config.common
    services.config.browser = _.extend common, services.config.browser

    # Redefine server port if port defined in command line parameter
    services.config.node.server.port = serverPort if serverPort
    services.config.node.server.port = 18180 if not services.config.node.server.port

    # Remove defaul configuration
    delete services.config.common
    global.appConfig = services.config

    global.config = services.config.node

    # Using javascript here to change global variable.
    `_console = _console`

    Rest.host = global.config.server.host
    Rest.port = global.config.server.port

    biFuture = Future.call(fs.readFile, path.join(baseUrl, 'assets/z/browser-init.id'), 'utf8').map (id) ->
      global.config.browserInitScriptId = id
    .mapFail ->
      true

    AppConfigLoader.ready().zip(biFuture).done (appConfig) ->
      router.addRoutes(appConfig.routes)
      router.addFallbackRoutes(appConfig.fallbackRoutes) if appConfig.fallbackRoutes?

      startServer ->
        timeLog "Server running at http://#{ Rest.host }:#{ Rest.port }/"
        timeLog "Current directory: #{ process.cwd() }"


exports.startServer = startServer = (callback) ->
  services.nodeServer = http.createServer (req, res) ->
    if (pos = req.url.indexOf('/XDR/')) != -1 # cross-domain request proxy
      services.xdrProxy(req.url.substr(pos + 5), req, res)
    else if req.url.indexOf('/REQUIRESTAT/collect') == 0
      services.statCollector(req, res)
    else if not services.router.process(req, res)
      req.addListener 'end', (err) ->
        services.fileServer.serve req, res, (err) ->
          if err
            res.writeHead err.status, err.headers
            if err.status is 404 or err.status is 500
              res.end "Error #{ err.status }"
            else
              res.end()
      .resume()
  .listen(global.config.server.port)
  callback?()

exports.restartServer = restartServer = ->
  stopServer()
  startServer ->
    timeLog "Server restart success"

exports.stopServer = stopServer = ->
  services.nodeServer.close()

timeLog = (message) ->
  console.log "#{(new Date).toLocaleTimeString()} - #{message}"

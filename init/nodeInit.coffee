`if (typeof define !== 'function') { define = require('amdefine')(module) }`

fs            = require 'fs'
path          = require 'path'
requirejs     = require 'requirejs'
_             = require 'underscore'

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
global._console = console

exports.init = (baseUrl = 'public', configName = 'default', serverPort) ->

  config = loadConfig(configName, serverPort)
  global.appConfig = config
  global.config    = config.node


  requirejs.config
    paths: require('../requirejs/pathConfig')
    baseUrl: baseUrl
    nodeRequire: require

  requirejs [
    'pathUtils'
    'cord!AppConfigLoader'
    'cord!Console'
    'cord!Rest'
    'cord!init/profilerInit'
    'cord!request/xdrProxy'
    'cord!requirejs/statCollector'
    'cord!router/serverSideRouter'
    'cord!utils/Future'
  ], (pathUtils, AppConfigLoader, Console, Rest, profilerInit, xdrProxy, statCollector, router, Future) ->
    pathUtils.setPublicPrefix(baseUrl)

    router.EventEmitter = EventEmitter
    services.router = router
    services.fileServer = new serverStatic.Server(baseUrl)
    services.xdrProxy = xdrProxy
    services.statCollector = statCollector

    global._console = Console

    Rest.host = global.config.server.host
    Rest.port = global.config.server.port

    biFuture = Future.call(fs.readFile, path.join(baseUrl, 'assets/z/browser-init.id'), 'utf8').map (id) ->
      global.config.browserInitScriptId = id
    .mapFail ->
      true

    profilerInit()

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


# Private functions

loadConfig = (configName, serverPort) ->
  try
    if configName.charAt(0) != '/'
      configName = pathDir + '/conf/' + configName + '.js'
    result = require(configName)

    # Merge node and browser configuration with common (defaults)
    common = _.clone(result.common)
    result.node = _.extend(common, result.node)

    common = _.clone(result.common)
    result.browser = _.extend(common, result.browser)

    # Redefine server port if port defined in command line parameter
    result.node.server.port = serverPort if serverPort
    result.node.server.port = 18180 if not result.node.server.port

    # Remove common configuration
    delete result.common

    timeLog "Loaded config from #{configName}"

    result
  catch e
    timeLog "Fail loading config from #{configName} with error #{e}"
    {}



timeLog = (message) ->
  console.log "#{(new Date).toLocaleTimeString()} - #{message}"

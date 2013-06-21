`if (typeof define !== 'function') { define = require('amdefine')(module) }`

fs            = require 'fs'
path          = require 'path'
requirejs     = require 'requirejs'

http          = require 'http'
serverStatic  = require 'node-static'

configPaths   = require './configPaths'

pathDir   = fs.realpathSync '.'

exports.services = services =
  nodeServer: null
  fileServer: null
  router: null

# Defaulting to standard console.
# Using javascript here to change global variable.
`_console = console`


exports.init = (baseUrl = 'public', configName = 'default', serverPort = 1337) ->
  requirejs.config
    baseUrl: baseUrl
    nodeRequire: require

  requirejs.config configPaths
  requirejs [
    'cord!AppConfigLoader'
    'cord!configPaths'
    'cord!Console'
    'cord!Rest'
    'cord!request/xdrProxy'
    'cord!router/serverSideRouter'
    'underscore'
  ], (AppConfigLoader, configPaths, _console, Rest, xdrProxy, router, _) ->
    configPaths.PUBLIC_PREFIX = baseUrl
    services.router = router
    services.fileServer = new serverStatic.Server(baseUrl)
    services.xdrProxy = xdrProxy

    # Loading configuration
    try
      services.config = require pathDir + '/conf/' + configName
      timeLog "Loaded config from " + pathDir + '/conf/' + configName + '.js'
    catch e
      services.config = {}
      timeLog "Fail loading config from " + pathDir + '/conf/' + configName + ".js with error " + e

    # Merge node and browser configuration with common (defaults)
    common = _.clone services.config.common
    services.config.node = _.extend common, services.config.node

    common = _.clone services.config.common
    services.config.browser = _.extend common, services.config.browser

    # Redefine server port if port defined in command line parameter
    services.config.node.server.port = serverPort if serverPort

    # Remove defaul configuration
    delete services.config.common
    global.appConfig = services.config

    global.config = services.config.node

    # Using javascript here to change global variable.
    `_console = _console`

    Rest.host = global.config.server.host
    Rest.port = global.config.server.port

    AppConfigLoader.ready().done (appConfig) ->
      router.addRoutes(appConfig.routes)

      startServer ->
        timeLog "Server running at http://#{ Rest.host }:#{ Rest.port }/"
        timeLog "Current directory: #{ process.cwd() }"


exports.startServer = startServer = (callback) ->
  services.nodeServer = http.createServer (req, res) ->
    if (pos = req.url.indexOf('/XDR/')) != -1 # cross-domain request proxy
      services.xdrProxy(req.url.substr(pos + 5), req, res)
    else if not services.router.process(req, res)
      req.addListener 'end', (err) ->
        services.fileServer.serve req, res, (err) ->
          if err
            if err.status is 404  or err.status is 500
              res.end "Error #{ err.status }"
            else
              res.writeHead err.status, err.headers;
              res.end()
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

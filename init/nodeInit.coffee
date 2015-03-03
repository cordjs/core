`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

fs            = require 'fs'
path          = require 'path'
requirejs     = require 'requirejs'
_             = require 'lodash'

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
global.CORD_IS_BROWSER = false

exports.init = (baseUrl = 'public', configName = 'default', serverPort) ->
  config = loadConfig(configName, serverPort)
  global.appConfig = config
  global.config    = config.node
  # need to be global because used to conditionally define dependencies throughout the project
  global.CORD_PROFILER_ENABLED = config.debug.profiler.enable


  # setting of this callback is necessary to avoid throwing global unhandled exception by requirejs when file not found
  requirejs.onError = (err) ->
    console.error 'ERROR while loading in REQUIREJS:', err

  requirejs.config
    paths: require('../requirejs/pathConfig')
    baseUrl: baseUrl
    nodeRequire: require

  requirejs [
    'pathUtils'
    'cord!AppConfigLoader'
    'cord!Console'
    if CORD_PROFILER_ENABLED then 'cord!init/profilerInit' else undefined
    'cord!request/xdrProxy'
    'cord!requirejs/statCollector'
    'cord!router/serverSideRouter'
    'cord!utils/Future'
  ], (pathUtils, AppConfigLoader, Console, profilerInit, xdrProxy, statCollector, router, Future) ->
    pathUtils.setPublicPrefix(baseUrl)

    router.EventEmitter = EventEmitter
    services.router = router
    services.fileServer = new serverStatic.Server(baseUrl)
    services.xdrProxy = xdrProxy
    services.statCollector = statCollector

    global._console = Console

    biFuture = Future.call(fs.readFile, path.join(baseUrl, 'assets/z/browser-init.id'), 'utf8').then (id) ->
      global.config.browserInitScriptId = id
    .catch ->
      true

    profilerInit() if CORD_PROFILER_ENABLED

    AppConfigLoader.ready().zip(biFuture).done (appConfig) ->
      router.addRoutes(appConfig.routes)
      router.addFallbackRoutes(appConfig.fallbackRoutes) if appConfig.fallbackRoutes?
      services.proxyRoutes = appConfig.proxyRoutes

      startServer ->
        timeLog "Server running at http://#{ global.config.server.host }:#{ global.config.server.port }/"
        timeLog "Current directory: #{ process.cwd() }"


exports.startServer = startServer = (callback) ->
  services.nodeServer = http.createServer (req, res) ->

    # Detect for proxyRoutes
    for proxyRoute in services.proxyRoutes
      if (pos = req.url.indexOf(proxyRoute)) != -1 # cross-domain request proxy
        return services.xdrProxy(req.url, req, res)

    if (pos = req.url.indexOf('/XDR/')) != -1 # cross-domain request proxy
      services.xdrProxy(req.url.substr(pos + 5), req, res)
    else if (pos = req.url.indexOf('/XDRS/')) != -1 # cross-domain request proxy with secrets
      services.xdrProxy(req.url.substr(pos + 6), req, res, true)
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

  require('./wsServer').start(services.nodeServer) if global.config.debug.livereload

  callback?()


exports.restartServer = restartServer = ->
  stopServer()
  startServer ->
    timeLog "Server restart success"


exports.stopServer = stopServer = ->
  services.nodeServer.close()


exports.loadConfig = loadConfig = (configName, serverPort) ->
  try
    if configName.charAt(0) != '/'
      configName = pathDir + '/conf/' + configName + '.js'
    result = require(configName)

    if _.isEmpty(result)
      console.warn("!!! Specified config file #{configName} is empty or misdefined.")

    # If default config exists, load it and merge with config
    defaultConfigPath = pathDir + '/conf/default.js'
    if fs.existsSync(defaultConfigPath)
      defaultConfig = require(defaultConfigPath)
      _.merge(defaultConfig.node, defaultConfig.common) # default.node <- default.common
      _.merge(defaultConfig.browser, defaultConfig.common) # default.browser <- default.common
      # result = _.merge(defaultConfig, result)

    # Redefine server port if port defined in command line parameter
    defaultConfig.common.server.port = serverPort if not isNaN(Number(serverPort))
    defaultConfig.common.server.port = 18180 if not defaultConfig.common.server.port

    if not defaultConfig.common.server.host
      defaultConfig.common.server.host = '127.0.0.1'

    if not defaultConfig.common.server.proto
      defaultConfig.common.server.proto = 'http'

    # Merge node and browser configuration with common (defaults)
    # Merge priorities: conf.node <- conf.common <- default.node <- default.common
    defaultNodeConfig = _.clone(defaultConfig.node)
    _.merge(defaultNodeConfig, result.common)
    result.node = _.merge(defaultNodeConfig, result.node)

    # The same for browser
    defaultBrowserConfig = _.clone(defaultConfig.browser)
    _.merge(defaultBrowserConfig, result.common)
    result.browser = _.merge(defaultBrowserConfig, result.browser)

    # Load secrets for node config
    if _.isString(result.node.secrets) and result.node.secrets.length
      secretsPath = result.node.secrets
      secretsPath = if secretsPath[0] == '/' then secretsPath else pathDir + '/conf/' + secretsPath
      secretsConf = require(secretsPath)
      result.node = _.extend(result.node, secretsConf) if _.isObject(secretsConf)

    # Redefine server port if port defined in command line parameter
    result.node.server.port = serverPort if not isNaN(Number(serverPort))
    result.node.server.port = 18180 if not result.node.server.port

    # Remove common configuration
    delete result.common

    timeLog "Loaded config from #{configName}"

    result
  catch e
    timeLog "Fail loading config from #{configName} with error #{e}"
    {}


# Private functions

timeLog = (message) ->
  console.log "#{(new Date).toLocaleTimeString()} - #{message}"

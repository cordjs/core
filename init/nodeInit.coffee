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
  global.CORD_PROFILER_ENABLED = global.config.debug.profiler.enable


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
    services.xdrProxy = xdrProxy
    services.statCollector = statCollector

    fileServer = new serverStatic.Server(baseUrl)
    fileServer.serve = fileServer.serve.bind(fileServer)
    if devSourcesServerRootDir = process.env['DEV_SOURCES_SERVER_ROOT_DIR']
      sourceServer = new serverStatic.Server(devSourcesServerRootDir)
      sourceServer.serve = sourceServer.serve.bind(sourceServer)

    services.staticServer = (req, res) =>
      req.addListener 'end', (err) ->
        Future.call(fileServer.serve, req, res).catch (err) =>
          if sourceServer?
            Future.call(sourceServer.serve, req, res)
          else
            throw err
        .catch (err) =>
          res.writeHead err.status, err.headers
          if err.status is 404 or err.status is 500
            res.end "Error #{ err.status }"
          else
            res.end()
      .resume()

    global._console = Console

    biFuture = Future.call(fs.readFile, path.join(baseUrl, 'assets/z/browser-init.id'), 'utf8').then (id) ->
      global.config.browserInitScriptId = id
    .catch ->
      true

    profilerInit() if CORD_PROFILER_ENABLED

    Future.sequence [
      AppConfigLoader.ready()
      biFuture
    ]
    .spread (appConfig) ->
      router.addRoutes(appConfig.routes)
      router.addFallbackRoutes(appConfig.fallbackRoutes) if appConfig.fallbackRoutes?
      services.proxyRoutes = appConfig.proxyRoutes

      startServer ->
        timeLog "Server running at http://#{ global.config.server.host }:#{ global.config.server.port }/"
        timeLog "Current directory: #{ process.cwd() }"


exports.startServer = startServer = (callback) ->
  services.nodeServer = http.createServer (req, res) ->

    if (pos = req.url.indexOf('/XDR/')) != -1 # cross-domain request proxy
      services.xdrProxy(services.router, req.url.substr(pos + 5), req, res)
    else if (pos = req.url.indexOf('/XDRS/')) != -1 # cross-domain request proxy with secrets
      services.xdrProxy(services.router, req.url.substr(pos + 6), req, res, true)
    else if req.url.indexOf('/REQUIRESTAT/collect') == 0
      services.statCollector(req, res)
    else if not services.router.process(req, res)
      # Detect for custom proxyRoutes from bundle configs
      for proxyRoute in services.proxyRoutes
        if (_.isRegExp(proxyRoute) and proxyRoute.test(req.url)) or (_.isString(proxyRoute) and -1 != req.url.indexOf(proxyRoute))
          services.xdrProxy(services.router, req.url, req, res)
          return

      services.staticServer(req, res)
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

    defaultConfig = null

    # Merge configs.
    # After a final merge we'll get the priorities:
    # (lowest) default.common -> default.node -> config.common -> confin.node (higest)
    # (lowest) default.common -> default.browser -> config.common -> confin.browser (higest)

    # If default config exists, load it and merge common -> node, common -> browser
    defaultConfigPath = pathDir + '/conf/default.js'
    if fs.existsSync(defaultConfigPath)
      defaultConfig = require(defaultConfigPath)
      defaultConfig.node    = _.merge({}, defaultConfig.common, defaultConfig.node)
      defaultConfig.browser = _.merge({}, defaultConfig.common, defaultConfig.browser)

    # Merge for main config common -> node, common -> browser
    result.node    = _.merge({}, result.common, result.node)
    result.browser = _.merge({}, result.common, result.browser)

    # Final merge with default config node -> node, browser -> browser
    if defaultConfig
      result.node    = _.merge({}, defaultConfig.node, result.node)
      result.browser = _.merge({}, defaultConfig.browser, result.browser)

    # Load secrets for node config
    if _.isString(result.node.secrets) and result.node.secrets.length
      secretsPath = result.node.secrets
      secretsPath = if secretsPath[0] == '/' then secretsPath else pathDir + '/conf/' + secretsPath
      secretsConf = require(secretsPath)
      result.node = _.extend(result.node, secretsConf) if _.isObject(secretsConf)

    # Redefine server port if port defined in command line parameter
    result.node.server.port = serverPort if not isNaN(Number(serverPort))
    result.node.server.port or= 18180

    result.node.server.host or= '127.0.0.1'
    result.node.server.proto or= 'http'

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

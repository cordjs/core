`if (typeof define !== 'function') { define = require('amdefine')(module) }`

fs            = require 'fs'
path          = require 'path'
requirejs     = require 'requirejs'

http          = require 'http'
serverStatic  = require 'node-static'

configPaths   = require './configPaths'

getNetworkInterfaceIps = ->
  interfaces = require('os').networkInterfaces()
  addresses = []
  for k of interfaces
      for k2 of interfaces[k]
          address = interfaces[k][k2]
          if address.family == 'IPv4' and not address.internal
              addresses.push(address.address)
  return addresses

host = getNetworkInterfaceIps().pop()
port          = '1337'

pathDir   = fs.realpathSync '.'

try global.CONFIG = require pathDir + '/conf/serverConf.json'
catch e
 global.CONFIG = {}

try global.CONFIG_CLIENT = require pathDir + '/conf/clientConf.json'
catch e
  global.CONFIG_CLIENT = {}


exports.services = services =
  nodeServer: null
  fileServer: null
  appManager: null

exports.init = (baseUrl = 'public') ->
  requirejs.config
    baseUrl: baseUrl
    nodeRequire: require

  requirejs.config configPaths
  requirejs [
    'cord!appManager'
    'cord!Rest'
    'cord!configPaths'
    'cord!request/xdrProxy'
  ], (application, Rest, configPaths, xdrProxy) ->
    configPaths.PUBLIC_PREFIX = baseUrl
    services.appManager = application
    services.fileServer = new serverStatic.Server(baseUrl)
    services.xdrProxy = xdrProxy

    Rest.host = host
    Rest.port = port
    startServer ->
      timeLog "Server running at http://#{ host }:#{ port }/"
      timeLog "Current directory: #{ process.cwd() }"

exports.startServer = startServer = (callback) ->
  services.nodeServer = http.createServer (req, res) ->
    if (pos = req.url.indexOf('/XDR/')) != -1 # cross-domain request proxy
      services.xdrProxy(req.url.substr(pos + 5), req, res)
    else if not services.appManager.process(req, res)
      req.addListener 'end', (err) ->
        services.fileServer.serve req, res, (err) ->
          if err
            if err.status is 404  or err.status is 500
              res.end "Error #{ err.status }"
            else
              res.writeHead err.status, err.headers;
              res.end()
  .listen(port)
  callback?()

exports.restartServer = restartServer = ->
  stopServer()
  startServer ->
    timeLog "Server restart success"

exports.stopServer = stopServer = ->
  services.nodeServer.close()

timeLog = (message) ->
  console.log "#{(new Date).toLocaleTimeString()} - #{message}"

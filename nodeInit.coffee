`if (typeof define !== 'function') { define = require('amdefine')(module) }`

fs            = require 'fs'
path          = require 'path'
requirejs     = require 'requirejs'

http          = require 'http'
serverStatic  = require 'node-static'

configPaths   = require './configPaths'
config        = require './config'
host          = '192.168.63.237'
port          = '80'

exports.services = services =
  nodeServer: null
  fileServer: null
  appManager: null

exports.init = (baseUrl = 'public') ->
  console.log 'public_prefix = ', config.PUBLIC_PREFIX
  requirejs.config
    baseUrl: baseUrl
    nodeRequire: require

  requirejs.config configPaths
  requirejs [
    'cord!appManager'
    'cord!Rest'
    'cord!config'
  ], (application, Rest, config) ->
    config.PUBLIC_PREFIX = baseUrl

    services.appManager = application
    services.fileServer = new serverStatic.Server(baseUrl)

    Rest.host = host
    Rest.port = port
    startServer ->
      timeLog "Server running at http://#{ host }:#{ port }/"
      timeLog "Current directory: #{ process.cwd() }"

exports.startServer = startServer = (callback) ->
  services.nodeServer = http.createServer (req, res) ->
    if !services.appManager.process req, res
      req.addListener 'end', (err) ->
        services.fileServer.serve req, res, (err) ->
          if err
            if err.status is 404  or err.status is 500
              res.end "Error #{ err.status }"
            else
              res.writeHead err.status, err.headers;
              res.end()
#  .listen(port, host)
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

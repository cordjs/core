`if (typeof define !== 'function') { define = require('amdefine')(module) }`

configPaths = require './configPaths'
requirejs = require 'requirejs'
requirejs.config
  nodeRequire: require
  baseUrl: 'target/'

requirejs.config configPaths

http = require 'http'
serverStatic = require 'node-static'

host = '127.0.0.1'
port = '1337'

nodeServer = null
fileServer = null
appManager = null

exports.startServer = startServer = (callback) ->
  nodeServer = http.createServer (req, res) ->
    if !appManager.process req, res
      req.addListener 'end', (err) ->
        fileServer.serve req, res, (err) ->
          if err
            if err.status is 404  or err.status is 500
              res.end "Error #{ err.status }"
            else
              res.writeHead err.status, err.headers;
              res.end()
  .listen port, host
  callback?()


exports.restartServer = restartServer = ->
#  console.log 'application: ', application
  stopServer()
  startServer ->
    timeLog "Server restart success"

exports.stopServer = stopServer = ->
  nodeServer.close()

timeLog = (message) ->
  console.log "#{(new Date).toLocaleTimeString()} - #{message}"

requirejs [
  'cord!appManager'
  'cord!Rest'
], (application, Rest) ->
  appManager = application
  fileServer = new serverStatic.Server './public/'

  Rest.host = host
  Rest.port = port
  startServer ->
    timeLog "Server running at http://#{ host }:#{ port }/"
    timeLog "Current directory: #{ process.cwd() }"

#  fileServer = new serverStatic.Server './public/'
#  http.createServer (req, res) ->
#    if !application.process req, res
#      req.addListener 'end', (err) ->
#        fileServer.serve req, res, (err) ->
#          if err
#            if err.status is 404  or err.status is 500
#              res.end "Error #{ err.status }"
#            else
#              res.writeHead err.status, err.headers;
#              res.end()
#              .listen port, host
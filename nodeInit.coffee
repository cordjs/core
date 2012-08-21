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

requirejs [
  'cord!appManager'
  'cord!Rest'
], (application, Rest) ->
    file = new serverStatic.Server './public/'

    Rest.host = host
    Rest.port = port

    http.createServer (req, res) ->
        if !application.process req, res
            req.addListener 'end', (err) ->
              file.serve req, res, (err) ->
                if err
                  if err.status is 404  or err.status is 500
                    res.end "Error #{ err.status }"
                  else
                    res.writeHead err.status, err.headers;
                    res.end()
    .listen port, host

    console.log "Server running at http://#{ host }:#{ port }/"
    console.log "Current directory: #{ process.cwd() }"
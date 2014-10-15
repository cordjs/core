###
Handler of web socket connections.
Used for debugging:
* livereload feature
###
WebSocketServer = require('ws').Server


exports.start = (httpServer) ->
  wss = new WebSocketServer(server: httpServer)
  wss.on 'connection', (ws) ->
    ws.on 'message', (msg) ->
      console.log 'ws: received message from browser', msg

  wss.on 'error', (err) ->
    console.error 'ws: error', err

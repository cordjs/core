define ->

  host = location.host

  currentTimeout = 100

  waitAndReload = ->
    ws = new WebSocket('ws://' + host)
    ws.onopen = -> location.reload()
    ws.onclose = ->
      setTimeout(waitAndReload, currentTimeout)
      currentTimeout += 10


  init: ->
    ###
    Initializes web-socket connection to the development server.
    Once the connection is closed it waits for the server to restart and then reloads the page.
    ###
    ws = new WebSocket('ws://' + host)
    ws.onclose = -> waitAndReload()

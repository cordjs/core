define ->

  host = location.host

  waitAndReload = ->
    console.log "reopen"
    ws = new WebSocket('ws://' + host)
    ws.onerror = ->
      ws.close()
      setTimeout(waitAndReload, 100)
    ws.onopen = -> location.reload()


  init: ->
    ###
    Initializes web-socket connection to the development server.
    Once the connection is closed it waits for the server to restart and then reloads the page.
    ###
    ws = new WebSocket('ws://' + host)
    ws.onclose = (evt) ->
      waitAndReload()

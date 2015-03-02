define [
  'http'
  'https'
  'underscore'
  'url'
], (http, https, _, url) ->

  (targetUrl, req, res, secrets = false) ->
    ###
    Cross-domain Request Proxy
    Very simple and low-level proxy function that just passes request to the target url and then passes result
     to the source browser.
    Headers are mostly preserved in both sides of transfer to imitate direct request from the browser.
    @node-only
    @param String targetUrl the target url to be requested
    @param IncomingMessage req the node's request
    @param ServerResponse res the node's response
    ###

    # In case if we need to proxy request with secrets, add them here
    if secrets and _.isObject(global.config.secrets)
      for secret, value of global.config.secrets
        targetUrl = targetUrl.replace('%23%7B' + secret + '%7D', value)
        targetUrl = targetUrl.replace('#{' + secret + '}', value)

    proxyUrl = url.parse(targetUrl)

    # copying headers and removing unnecessary ones
    headers = _.clone(req.headers)
    delete headers.cookie
    delete headers.host
    delete headers.connection

    options =
      method: req.method ? 'GET'
      hostname: proxyUrl.hostname ? global.config.api.backend.host
      port: proxyUrl.port
      path: proxyUrl.path
      headers: headers
      rejectUnauthorized: false

    protoString = proxyUrl.protocol or global.config.api.backend.protocol
    protocol =
      if protoString == 'http:' or protoString == 'http'
        http
      else
        https

    proxyReq = protocol.request options, (proxyRes) ->
      # send http-headers back to the browser copying them from the target server response
      res.writeHead proxyRes.statusCode, proxyRes.headers
      # read all data from the target server response and pass it to the browser response
      proxyRes.on 'data', (chunk) -> res.write(chunk)
      proxyRes.on 'end', -> res.end()

    proxyReq.on 'error', (e) ->
      _console.error 'Problem with proxy request: ', options, e
      res.writeHead(500, 'Bad request!', 'Content-type': 'text/html')
      res.end """
        <html>
          <head><title>Error 500</title></head>
          <body><h1>Unexpected Error occurred!</h1></body>
        </html>
      """


    # read all data from the browser request and pass it to the target server
    req.on 'data', (chunk) -> proxyReq.write(chunk)
    req.on 'end', -> proxyReq.end()

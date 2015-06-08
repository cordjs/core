define [
  'http'
  'https'
  'underscore'
  'url'
], (http, https, _, url) ->

  (router, targetUrl, req, res, secrets = false) ->
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

    resolvedConfig = router.prepareConfigForRequest(req)
    nodeConfig = resolvedConfig.node

    # In case if we need to proxy request with secrets, add them here
    if secrets and _.isObject(nodeConfig.secrets)
      for secret, value of nodeConfig.secrets
        targetUrl = targetUrl.replace('%23%7B' + secret + '%7D', value)
        targetUrl = targetUrl.replace('#{' + secret + '}', value)

    proxyUrl = url.parse(targetUrl)

    # copying headers and removing unnecessary ones
    headers = _.clone(req.headers)
    newCookie = ''
    if matches = /XDEBUG_SESSION=\w+/.exec(headers.cookie)
      newCookie = matches[0]
    delete headers.cookie
    headers.cookie = newCookie
    delete headers.host
    delete headers.connection

    options =
      method: req.method ? 'GET'
      hostname: proxyUrl.hostname ? nodeConfig.api.backend.host
      port: proxyUrl.port
      path: proxyUrl.path
      headers: headers
      rejectUnauthorized: false

    protoString = proxyUrl.protocol or nodeConfig.api.backend.protocol
    protocol =
      if protoString == 'http:' or protoString == 'http'
        http
      else
        https

    proxyReq = protocol.request options, (proxyRes) ->
      # send http-headers back to the browser copying them from the target server response
      headers = proxyRes.headers
      headers['X-Target-Host'] = options.hostname if not proxyRes.headers['X-Target-Host']? and not proxyRes.headers['x-target-host']?
      res.writeHead proxyRes.statusCode, proxyRes.headers
      # read all data from the target server response and pass it to the browser response
      proxyRes.on 'data', (chunk) -> res.write(chunk)
      proxyRes.on 'end', -> res.end()

    proxyReq.on 'error', (e) ->
      console.error 'Problem with proxy request: ', options, e
      res.writeHead(502, 'XDR failed', 'Content-type': 'application/json')
      res.end JSON.stringify
        error: code: e.code ? String(e)


    # read all data from the browser request and pass it to the target server
    req.on 'data', (chunk) -> proxyReq.write(chunk)
    req.on 'end', -> proxyReq.end()

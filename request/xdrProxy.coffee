define [
  'http'
  'underscore'
  'url'
], (http, _, url) ->

  (targetUrl, req, res) ->
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
    proxyUrl = url.parse(decodeURIComponent(targetUrl))

    # copying headers and removing unnecessary ones
    headers = _.clone(req.headers)
    delete headers.cookie
    delete headers.host
    delete headers.connection

    options =
      method: req.method
      hostname: proxyUrl.hostname
      port: proxyUrl.port
      path: proxyUrl.path
      headers: headers

    proxyReq = http.request options, (proxyRes) ->
      # send http-headers back to the browser copying them from the target server response
      res.writeHead proxyRes.statusCode, proxyRes.headers
      # read all data from the target server response and pass it to the browser response
      proxyRes.on 'data', (chunk) -> res.write(chunk)
      proxyRes.on 'end', -> res.end()

    proxyReq.on 'error', (e) ->
      console.log 'Problem with proxy request: ', e

    # read all data from the browser request and pass it to the target server
    req.on 'data', (chunk) -> proxyReq.write(chunk)
    req.on 'end', -> proxyReq.end()

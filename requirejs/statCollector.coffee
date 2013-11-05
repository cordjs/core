define [
  'fs'
  'http'
  'https'
  'underscore'
  'url'
  'querystring'
], (fs, http, https, _, url, qs) ->

  (req, res) ->
    statFile = 'require-stat.json'
    body = ''
    req.on 'data', (chunk) -> body += chunk
    req.on 'end', ->
      post = qs.parse(body)
      fs.readFile statFile, (err, data) ->
        stat = if err then {} else JSON.parse(data)
        stat[post.root] = post['definedModules[]'].sort()
        fs.writeFile statFile, JSON.stringify(stat, null, 2), (err)->
          throw err if err

    res.end("<pre>#{ JSON.stringify(body, null, 2) }</pre>")

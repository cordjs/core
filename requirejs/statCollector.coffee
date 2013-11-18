define [
  'fs'
  'http'
  'https'
  'underscore'
  'url'
  'querystring'
], (fs, http, https, _, url, qs) ->

  (req, res) ->
    jsStatFile  = 'require-stat.json'
    cssStatFile = 'css-stat.json'
    body = ''
    req.on 'data', (chunk) -> body += chunk
    req.on 'end', ->
      post = qs.parse(body)
      fs.readFile jsStatFile, (err, data) ->
        stat = if err then {} else JSON.parse(data)
        stat[post.root] = post['definedModules[]'].sort()
        fs.writeFile jsStatFile, JSON.stringify(stat, null, 2), (err)->
          throw err if err
      fs.readFile cssStatFile, (err, data) ->
        stat = if err then {} else JSON.parse(data)
        stat[post.root] = post['css[]'].sort()
        fs.writeFile cssStatFile, JSON.stringify(stat, null, 2), (err)->
          throw err if err

    res.end("<pre>#{ JSON.stringify(body, null, 2) }</pre>")

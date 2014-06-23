define [
  'fs'
  'underscore'
  'querystring'
], (fs, _, qs) ->

  (req, res) ->
    jsStatFile  = 'require-stat.json'
    cssStatFile = 'css-stat.json'
    body = ''
    req.on 'data', (chunk) -> body += chunk
    req.on 'end', ->
      post = qs.parse(body)
      fs.readFile jsStatFile, (err, data) ->
        stat = if err then {} else JSON.parse(data)
        current = stat[post.root] ? []
        stat[post.root] = _.uniq(post['definedModules[]'].concat(current).sort(), true)
        fs.writeFile jsStatFile, JSON.stringify(stat, null, 2), (err) ->
          throw err if err
      fs.readFile cssStatFile, (err, data) ->
        stat = if err then {} else JSON.parse(data)
        current = stat[post.root] ? []
        stat[post.root] = _.uniq(post['css[]'].concat(current).sort(), true)
        fs.writeFile cssStatFile, JSON.stringify(stat, null, 2), (err) ->
          throw err if err

    res.end("<pre>#{ JSON.stringify(body, null, 2) }</pre>")

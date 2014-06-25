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
        try
          stat = if err then {} else JSON.parse(data)
          current = stat[post.root] ? []
          stat[post.root] = _.uniq(post['definedModules[]'].concat(current).sort(), true)
          fs.writeFile jsStatFile, JSON.stringify(stat, null, 2), (err) ->
            throw err if err
        catch err
          console.error("Error while parsing or writing require-stat!", err, data)
      fs.readFile cssStatFile, (err, data) ->
        try
          stat = if err then {} else JSON.parse(data)
          current = stat[post.root] ? []
          # WARNING! It's not allowed to sort list of CSS-filed due to possibility to break dependency order of the CSS
          stat[post.root] = _.uniq(current.concat(post['css[]']))
          fs.writeFile cssStatFile, JSON.stringify(stat, null, 2), (err) ->
            throw err if err
        catch err
          console.error("Error while parsing or writing css-stat!", err, data)

    res.end("<pre>#{ JSON.stringify(body, null, 2) }</pre>")

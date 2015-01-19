define ->
  (encodedText) ->
    new Buffer(encodedText, 'base64').toString('utf8')
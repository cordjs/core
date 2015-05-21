define [
  './' + (if CORD_IS_BROWSER then 'browser' else 'server') + '/base64decode'
], (base64decode) ->
  base64decode
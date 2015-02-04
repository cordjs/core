define [
  'postal'
  'underscore'
], (postal, _) ->

  config = global.config


  stringify = (args) ->
    result = ''

    for arg in args
      if arg instanceof Object
        try
          # TypeError: Converting circular structure to JSON
          result += JSON.stringify(arg) + ', '
          result += JSON.stringify(arg[3].stack) if arg[3] != undefined and arg[3].stack != ''
        catch
          result += arg + ', '
      else
        result += arg + ', '

    return result


  addDatePrefix = (args) ->
    if not _.isArray(args)
      args = if args then [args] else []

    args.unshift(new Date) if not CORD_IS_BROWSER
    args


  self =
    ###
    Обертка для консоли, служит для того, чтобы включать/выключать вывод в конфиге
    ###

    log: (args...) ->
      console.log.apply(console, addDatePrefix(args)) if config?.console.log or not config
      return


    warn: (args...) ->
      console.warn.apply(console, addDatePrefix(args)) if config?.console.warn or not config

      message = stringify(arguments)
      postal.publish 'logger.log.publish', { tags: ['warning'], params: {warning: message} }
      return


    error: (args...) ->
      #console.log x.stack for x in arguments when x and x.stack # advanced debugging
      self.taggedError.apply(self, [['error']].concat(args))


    taggedError: (tags, args...) ->
      console.error.apply(console, addDatePrefix(args)) if config?.console.error or not config

      message = stringify(args)
      postal.publish 'error.notify.publish', { message: 'Произошла ошибка', link: '', details: message }
      error = _.find(args, (item) -> item and item.stack)
      excludeErrors = config?.console.excludeErrors or []
      if error and not (error.name in excludeErrors)
        postal.publish 'logger.log.publish', { tags: tags, params: {error: message} }

      return


    clear: ->
      console.clear?()
      return

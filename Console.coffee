define [
  'postal'
  'underscore'
], (postal, _) ->

  config = global.config

  excludeErrors = []
  outputLog = outputWarn = outputError = outputErrorTrace = true

  if config and config.console
    outputLog = config.console.log
    outputWarn = config.console.warn
    outputError = config.console.error
    outputErrorTrace = config.console.errorTrace or outputErrorTrace
    excludeErrors = config.console.excludeErrors or excludeErrors

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


  addErrorTrace = (error, args) ->
    args.push(error.stack) if error and not _.find(args, (item) -> item == error.stack)
    args

  self =
    ###
    Обертка для консоли, служит для того, чтобы включать/выключать вывод в конфиге
    ###

    log: (args...) ->
      console.log.apply(console, addDatePrefix(args)) if outputLog
      return


    warn: (args...) ->
      console.warn.apply(console, addDatePrefix(args)) if outputWarn

      message = stringify(arguments)
      postal.publish 'logger.log.publish', { tags: ['warning'], params: {warning: message} }
      return


    error: (args...) ->
      #console.log x.stack for x in arguments when x and x.stack # advanced debugging
      self.taggedError.apply(self, [['error']].concat(args))


    taggedError: (tags, args...) ->
      ###
      Выводит ошибку в консоль и оповещает Logger
      @param tags {Array} Тэги ошибки. Например: ['error'] | ['warning']
      @param args {Mixed} Сообщения об ошибке и/или экземпляр Error
      ###
      error = _.find(args, (item) -> item and item.stack)

      if outputError
        args = addErrorTrace(error, args) if outputErrorTrace
        console.error.apply(console, addDatePrefix(args))

      args = addErrorTrace(error, args) if not outputError or not outputErrorTrace
      message = stringify(args)
      postal.publish 'error.notify.publish', { message: 'Произошла ошибка', link: '', details: message }

      if not error or not error.type or not (error.type in excludeErrors)
        postal.publish 'logger.log.publish', { tags: tags, params: {error: message} }

      return


    clear: ->
      console.clear?()
      return

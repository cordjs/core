define [
  'postal'
  'underscore'
], (postal, _) ->

  config = global.config

  excludeErrors = []
  outputLog = outputWarn = outputError = true
  outputErrorTrace = false

  if config and config.console
    outputLog = config.console.log
    outputWarn = config.console.warn
    outputError = config.console.error
    outputErrorTrace = !!config.console.errorTrace
    excludeErrors = config.console.excludeErrors or excludeErrors


  stringify = (args) ->
    args.map (x) ->
      if x instanceof Object
        try
          # TypeError: Converting circular structure to JSON
          JSON.stringify(x)
        catch
          x
      else
        x
    .join(', ')


  prependDate = (args) ->
    args.unshift((new Date).toString()) if not CORD_IS_BROWSER
    args


  appendErrorTrace = (args, error) ->
    if error and not _.find(args, (item) -> item == error.stack)
      args.push("\n---------------\n")
      args.push(error.stack)
    args


  self =
    ###
    System console wrapper with nice configurable debugging and logging features
    ###

    _trace: ->
      (new Error).stack.split("\n")


    log: (args...) ->
      if outputLog
        args.unshift @_trace()[3]
        console.log stringify(prependDate(args))


    warn: (args...) ->
      postal.publish 'logger.log.publish',
        tags: ['warning']
        params:
          warning: stringify(args)

      if outputWarn
        args.unshift @_trace()[3]
        console.warn stringify(prependDate(args))


    error: (args...) ->
      @_taggedError @_trace(), ['error'], args


    taggedError: (tags, args...) ->
      @_taggedError @_trace(), tags, args


    _taggedError: (trace, tags, args...) ->
      ###
      Smart console.error:
       * appends stack-trace of Error-typed argument if configured
       * sends error information to logger
       * displays error in console if configured
      @param {Array} tags - tags for logging, e.g. ['error'] | ['warning']
      @param {Any} args - usual console.error arguments
      ###
      if outputErrorTrace
        error = _.find(args, (item) -> item and item.stack)
        appendErrorTrace(args, error)

      message = stringify(args)
      postal.publish 'error.notify.publish',
        message: 'Произошла ошибка'
        link: ''
        details: message

      if not error or not error.type or not (error.type in excludeErrors)
        postal.publish 'logger.log.publish',
          tags: tags
          params:
            error: message

      if outputError
        args.unshift trace[3]
        console.error stringify(prependDate(args))


    clear: ->
      console.clear?()
      return


    assertLazy: (errorMessage, checkFunction) ->
      ###
      Checks that checkFunction() value is true. Otherwise throws an error with errorMessage text.
      ###
      if config.debug.assertions and not checkFunction()
        throw new Error("Assertion failed. #{errorMessage}")
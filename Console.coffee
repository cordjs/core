define [
  'cord!errors'
  'postal'
  'underscore'
], (errors, postal, _) ->
  ###
  System console wrapper with nice configurable debugging and logging features
  ###

  # What kind of messages we should log
  consoleConfig = global?.config?.console or {}
  output =
    log: consoleConfig.log or true
    warn: consoleConfig.warn or true
    error: consoleConfig.error or true
    notice: consoleConfig.notice or false
    internal: consoleConfig.internal or false
    errorTrace: consoleConfig.errorTrace or false
    appendConsoleCallTrace: consoleConfig.appendConsoleCallTrace or false

  # Enable assertions (for development only)
  assertionsEnabled = global?.config?.debug.assertions or false


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


  prepareArgs = (args) ->
    if not CORD_IS_BROWSER
      host = global?.config?.api.backend.host
      args.unshift host if host
      args.unshift((new Date).toString())
    args


  getConsoleCallTraceLine = ->
    ###
    Returns first line without Console.js from the current call stack-trace.
    @return {String|undefined}
    ###
    lines = (new Error).stack.split("\n").slice(1)
    _.find lines, (x) ->
      x.indexOf('/cord/core/Console.js') == -1


  _log = (type, args) ->
    if output[type]
      postal.publish 'logger.log.publish',
        tags: [type]
        params:
          message: stringify(args)
          console: true

      # Add console call trace line
      args.push("\n_console.#{type} called here:\n" + getConsoleCallTraceLine())  if output.appendConsoleCallTrace

      method = if console[type] then type else 'log'
      args.unshift "[#{type}]"
      console[method] prepareArgs(args).join(" ")


  _minErrorType = (type1, type2) ->
    typeWeight =
      error: 5
      warn: 4
      log: 3
      notice: 2
      internal: 1

    weight1 = typeWeight[type1] or typeWeight['log']
    weight2 = typeWeight[type2] or typeWeight['log']

    if weight1 > weight2 then type2 else type1


  _taggedError = (tags, errorType, args) ->
    ###
    Smart console.error:
     * appends stack-trace of Error-typed argument if configured
     * sends error information to logger
     * displays error in console if configured
    @param {Array} tags - tags for logging, e.g. ['error'] | ['warning']
    @param {Any} args - usual console.error arguments
    ###

    # Get error type from args
    for item in args when item and item.stack
      errorType = _minErrorType(errorType, errors.getType(item))

    args = args.map (item) ->
      if item and item.stack
        if output.errorTrace then "\n#{item.stack}\n" else item.message
      else
        item

    # Report the error so that we could show it to the user
    if errorType == 'error'
      postal.publish 'error.notify.publish',
        message: 'Произошла ошибка'
        console: true
        link: ''
        details: stringify(args)

    # And log the error
    _log errorType, args if output[errorType]


  ## export ##

  log: (args...) ->
    _log 'log', args


  warn: (args...) ->
    _taggedError [], 'warn', args


  error: (args...) ->
    _taggedError [], 'error', args


  taggedError: (tags, args...) ->
    _taggedError tags, 'error', args


  clear: ->
    console.clear?()
    return


  assertLazy: (errorMessage, checkFunction) ->
    ###
    Checks that checkFunction() value is true. Otherwise throws an error with errorMessage text.
    ###
    if assertionsEnabled and not checkFunction()
      throw new Error("Assertion failed. #{errorMessage}")

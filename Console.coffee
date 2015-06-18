define [
  'cord!errors'
  'postal'
  'underscore'
], (errors, postal, _) ->

  # What kind of messages we should log
  consoleConfig = global?.config?.console or {}
  output =
    log: consoleConfig.log or true
    warn: consoleConfig.warn or true
    error: consoleConfig.error or true
    notice: consoleConfig.notice or false
    internal: consoleConfig.internal or false
    errorTrace: consoleConfig.errorTrace or false

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


  addErrorTrace = (args, trace) ->
    args.push("\n" + trace) if trace
    args


  self =
    ###
    System console wrapper with nice configurable debugging and logging features
    ###

    _trace: () ->
      ###
      Smart trace. It removes all lines inside Console.coffee so the first line will be the caller.
      ###
      stack = (new Error).stack
      if stack
        lines = stack.split("\n").slice(1)
        # There should be a better way :(
        while (lines[0]?.indexOf('/cord/core/Console.') >= 0)
          lines = lines.slice(1)
        lines.join("\n")
      else
        ''


    _log: (type, args) ->
      if output[type]
        postal.publish 'logger.log.publish',
          tags: [type]
          params:
            message: stringify(args)
            console: true

        # Add trace information
        if output.errorTrace and (type == 'warn' or type == 'error')
          addErrorTrace args, "    ------------------\n" + @_trace()
        else
          args.push @_trace().split("\n")[0].trim()

        method = if console[type] then type else 'log'
        args.unshift "[#{type}]"
        console[method] prepareArgs(args).join(" ")


    log: (args...) ->
      @_log 'log', args


    warn: (args...) ->
      @_taggedError [], 'warn', args


    error: (args...) ->
      @_taggedError [], 'error', args


    _minErrorType: (type1, type2) ->
      typeWeight =
        error: 5
        warn: 4
        log: 3
        notice: 2
        internal: 1

      weight1 = typeWeight[type1] or typeWeight['log']
      weight2 = typeWeight[type2] or typeWeight['log']

      if weight1 > weight2 then type2 else type1


    taggedError: (tags, args...) ->
      @_taggedError tags, args, 'error'


    _taggedError: (tags, errorType, args) ->
      ###
      Smart console.error:
       * appends stack-trace of Error-typed argument if configured
       * sends error information to logger
       * displays error in console if configured
      @param {Array} tags - tags for logging, e.g. ['error'] | ['warning']
      @param {Any} args - usual console.error arguments
      ###

      # Get error type from args
      for item in args
        if item.stack
          errorType = @_minErrorType(errorType, errors.getType(item))

      args = _.map args, (item) ->
        if item.stack
          if output.errorTrace then item.stack else item.message
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
      @_log errorType, args if output[errorType]


    clear: ->
      console.clear?()
      return


    assertLazy: (errorMessage, checkFunction) ->
      ###
      Checks that checkFunction() value is true. Otherwise throws an error with errorMessage text.
      ###
      if assertionsEnabled and not checkFunction()
        throw new Error("Assertion failed. #{errorMessage}")

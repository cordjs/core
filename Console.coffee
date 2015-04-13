define [
  'cord!errors'
  'postal'
  'underscore'
], (errors, postal, _) ->

  # What kind of messages we should log
  output =
    log: global?.config?.console.log or true
    warn: global?.config?.console.warn or true
    error: global?.config?.console.error or true
    notice: global?.config?.console.notice or false
    system: global?.config?.console.system or false
    errorTrace: global?.config?.console.errorTrace or false
    joinArgs: global?.config?.console.joinArgs or false

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


  addDate = (args) ->
    args.unshift((new Date).toString()) if not CORD_IS_BROWSER
    if output.joinArgs
      [args.join('\n')]
    else
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
      lines = (new Error).stack.split("\n").slice(1)
      # There should be a better way :(
      while (lines[0]?.indexOf('/cord/core/Console.') >= 0)
        lines = lines.slice(1)
      lines.join("\n")


    _log: (type, args) ->
      if output[type]
        postal.publish 'logger.log.publish',
          tags: [type]
          params:
            message: stringify(args)
            console: true

        # Add trace information for non-error types
        if output.errorTrace and (type == 'warn' or type == 'error')
          addErrorTrace args, "    ------------------\n" + @_trace()
        else
          args.push @_trace().split("\n")[0]

        method = if console[type] then type else 'log'
        args.unshift "[#{type}]"
        console[method] addDate(args).join(" ")


    log: (args...) ->
      @_log 'log', args


    warn: (args...) ->
      @_log 'warn', args


    error: (args...) ->
      @_taggedError @_trace(), ['error'], args


    taggedError: (tags, args...) ->
      @_taggedError @_trace(), tags, args


    _taggedError: (trace, tags, args) ->
      ###
      Smart console.error:
       * appends stack-trace of Error-typed argument if configured
       * sends error information to logger
       * displays error in console if configured
      @param {Array} tags - tags for logging, e.g. ['error'] | ['warning']
      @param {Any} args - usual console.error arguments
      ###
      if output.errorTrace
        error = _.find(args, (item) -> item and item.stack)
        if error and error.stack
          trace = error.stack
          # Remove errors from args. We already have a stack trace
          args = _.filter args, (item) -> not item.stack
        addErrorTrace args, trace

      errorType = (error and error.type) or 'error'

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

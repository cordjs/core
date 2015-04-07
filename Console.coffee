define [
  'postal'
  'underscore'
], (postal, _) ->

  # What kind of messages we should log
  output =
    log: global?.config?.console.log or true
    warn: global?.config?.console.warn or true
    error: global?.config?.console.error or true
    notice: global?.config?.console.notice or false
    system: global?.config?.console.system or false
    errorTrace: global?.config?.console.errorTrace or false

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
    args


  addErrorTrace = (args, trace) ->
    args.push(trace) if trace
    args


  self =
    ###
    System console wrapper with nice configurable debugging and logging features
    ###

    _trace: (linesFrom = 0) ->
      (new Error).stack.split("\n").slice(linesFrom+1).join("\n")


    _log: (type, args) ->
      if output[type]
        postal.publish 'logger.log.publish',
          tags: [type]
          params:
            message: stringify(args)
            console: true

        # We need trace only for error messages
        if output.errorTrace and (type == 'error' or type == 'warn')
          addErrorTrace args, @_trace(3)
        else
          args.push @_trace(3).split("\n")[0]

        method = if console[type] then type else 'log'
        console[method].apply(console, addDate(args))


    log: (args...) ->
      @_log 'log', args


    warn: (args...) ->
      @_log 'warn', args


    error: (args...) ->
      @_taggedError @_trace(2), ['error'], args


    taggedError: (tags, args...) ->
      @_taggedError @_trace(2), tags, args


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
        addErrorTrace args, trace

      errorType = (error and error.type) or 'error'

      if output[errorType]
        postal.publish 'error.notify.publish',
          message: 'Произошла ошибка'
          console: true
          link: ''
          details: stringify(args)

        @_log errorType, args


    clear: ->
      console.clear?()
      return


    assertLazy: (errorMessage, checkFunction) ->
      ###
      Checks that checkFunction() value is true. Otherwise throws an error with errorMessage text.
      ###
      if assertionsEnabled and not checkFunction()
        throw new Error("Assertion failed. #{errorMessage}")
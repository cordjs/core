define [
  'postal'
  'underscore'
], (postal, _) ->

  class Console
    ###

      Обертка для консоли, служит для того, чтобы включать/выключать вывод в конфиге

    ###

    @getConfig: ->
      @config = global.config if @config == undefined
      @config


    @stringify: (args) ->
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


    @addPrefix: (args) ->
      if not _.isArray(args)
        args = if args then [args] else []

      args.unshift(new Date())
      args


    @log: (args...)->
      config = @getConfig()

      console.log.apply console, @addPrefix(args) if config?.console.log or not config

      # postal?.publish 'log', JSON.stringify(arguments)
      return


    @warn: (args...)->
      config = @getConfig()

      console.warn.apply console, @addPrefix(args) if config?.console.warn or not config

      message = Console.stringify arguments
      postal.publish 'logger.log.publish', { tags: ['warning'], params: {warning: message} }
      # postal?.publish 'log', JSON.stringify(arguments)
      return


    @error: (args...)->
      Console.taggedError ['error'], arguments
      args =
        try
          JSON.stringify(args)
        catch
          # TypeError: Converting circular structure to JSON
          arguments

      # postal?.publish 'log', args


    @taggedError: (tags, args...) ->
      config = @getConfig()

      console.error.apply console, @addPrefix(arguments) if config?.console.error or not config

      message = Console.stringify args
      postal.publish 'error.notify.publish', { message: 'Произошла ошибка', link: '', details: message }
      postal.publish 'logger.log.publish', { tags: tags, params: {error: message} }

      return


    @clear: ->
      console.clear?()

      return

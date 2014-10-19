define [
  'postal'
], (postal) ->

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


    @log: ->
      config = @getConfig()

      console.log.apply console, arguments if config?.console.log or not config

      postal?.publish 'log', JSON.stringify(arguments)
      return


    @warn: ->
      config = @getConfig()

      console.warn.apply console, arguments if config?.console.warn or not config

      message = Console.stringify arguments
      postal.publish 'logger.log.publish', { tags: ['warning'], params: {warning: message} }
      postal?.publish 'log', JSON.stringify(arguments)
      return


    @error: ->
      Console.taggedError ['error'], arguments
      args =
        try
          JSON.stringify(arguments)
        catch
          # TypeError: Converting circular structure to JSON
          arguments
      postal?.publish 'log', args


    @taggedError: (tags, args...) ->
      config = @getConfig()

      console.error.apply console, arguments if config?.console.error or not config

      message = Console.stringify args
      postal.publish 'error.notify.publish', { message: 'Произошла ошибка', link: '', details: message }
      postal.publish 'logger.log.publish', { tags: tags, params: {error: message} }

      return


    @clear: ->
      console.clear?()

      return

define [
  'postal'
], (postal) ->

  class Console
    ###

      Обертка для консоли, служит для того, чтобы включать/выключать вывод в конфиге

    ###

    @getConfig: ->
      @config = global.config if @config == undefined

      return @config


    @stringify: (args) ->
      result = ''

      for arg in args
        if arg instanceof Object
          try
            # TypeError: Converting circular structure to JSON
            result += JSON.stringify(arg) + ', '
          catch
            result += arg + ', '
        else
          result += arg + ', '

      return result


    @log: ->
      config = @getConfig()

      console.log.apply console, arguments if config?.console.log or not config

      return


    @warn: ->
      config = @getConfig()

      console.warn.apply console, arguments if config?.console.warn or not config

      message = Console.stringify arguments
      postal.publish 'logger.log.publish', { tags: ['warning'], params: {warning: message} }

      return


    @error: ->
      Console.taggedError ['error'], arguments


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

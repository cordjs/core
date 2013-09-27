define [
], () ->

  class Console
    ###

      Обертка для консоли, служит для того, чтобы включать/выключать вывод в конфиге

    ###

    @getConfig: ->
      @config = global.config if @config == undefined

      return @config

    @log: ->
      config = @getConfig()

      console.log.apply console, arguments if config?.console.log or not config

      return


    @warn: ->
      config = @getConfig()

      console.warn.apply console, arguments if config?.console.warn or not config

      postal.publish 'logger.log.publish', { tags: ['warning'], params: {warning: arguments} }

      return


    @error: ->
      config = @getConfig()

      console.error.apply console, arguments if config?.console.error or not config

      postal.publish 'logger.log.publish', { tags: ['error'], params: {error: arguments} }

      return


    @clear: ->
      console.clear?()

      return

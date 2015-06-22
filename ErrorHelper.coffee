define [
  'cord!request/errors'
], (httpErrors) ->

  class ErrorHelper

    @inject: ['translator', 'config']

    getMessageHr: (error) ->
      message = @translator.translate2(
        if error instanceof httpErrors.Network
          'Network error'
        else
          'Common error'
        context: 'errors'
      )
      message += ": #{error.message.substring(0,255)}" if @config.debug.showMobileErrors

      message

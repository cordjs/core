define [
  'cord!request/errors'
], (httpErrors) ->

  class ErrorHelper

    @inject: ['translator']

    getMessageHr: (error) ->
      @translator.translate2(
        if error instanceof httpErrors.Http
          'Network error'
        else
          'Common error'
        context: 'errors'
      )
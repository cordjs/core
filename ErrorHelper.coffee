define [
  'cord!request/errors'
  'cord!errors'
], (httpErrors, errors) ->

  class ErrorHelper

    @inject: ['translator', 'config']

    getMessageHr: (error) ->
      switch
        when error instanceof httpErrors.InvalidResponse
          message = @_getMessageHrFromInvalidResponse(error)
        when error instanceof errors.TranslatedError
          message = error.message
        else
          message = @translator.translate2(
            switch
              when error instanceof httpErrors.Network then 'Network error'
              else 'Common error'
            context: 'errors'
          )
          message += ": #{error.message.substring(0,255)}" if @config.debug.showMobileErrors

      message


    _getMessageHrFromInvalidResponse: (error) ->
      ###
      Get correct error message from InvalidResponse error
      ###
      switch
        when error.response.body._message? then error.response.body._message
        else error.message

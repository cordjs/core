define ->
  ###
  Custom exception classes used in the framework's core
  ###

  isInternal: isInternal = (err) ->
    err.isCordInternal or err.message?.match /Chunk error.*(WidgetSentenced|WidgetParamsRace)/


  CordError: class CordError extends Error
    ###
    Base error class
    ###
    name: 'CordError'
    type: 'error'
    message: ''
    isCordInternal: false

    constructor: (message, type) ->
      @message = message
      @isCordInternal = isInternal(@)
      if type
        @type = type
      else if @isCordInternal
        @type = 'internal'
      Error.call(this, message)
      Error.captureStackTrace?(this, arguments.callee)


  WidgetDropped: class WidgetDropped extends CordError
    name: 'WidgetDropped'
    isCordInternal: true


  WidgetSentenced: class WidgetSentenced extends CordError
    name: 'WidgetSentenced'
    isCordInternal: true


  BehaviourCleaned: class BehaviourCleaned extends CordError
    name: 'BehaviourCleaned'
    isCordInternal: true


  WidgetParamsRace: class WidgetParamsRace extends CordError
    name: 'WidgetParamsRace'
    isCordInternal: true


  MustReloadPage: class MustReloadPage extends CordError
    name: 'MustReloadPage'
    isCordInternal: true


  MegaIdAuthFailed: class MegaIdAuthFailed extends CordError
    name: 'MegaIdAuthFailed'


  AuthError: class AuthError extends CordError
    name: 'AuthError'


  ConfigError: class ConfigError extends CordError
    name: 'ConfigError'

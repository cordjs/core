define ->
  ###
  Custom exception classes used in the framework's core
  ###

  isInternal: isInternal = (err) ->
    err.isCordInternal or err.message?.match /Chunk error.*(WidgetSentenced|WidgetParamsRace)/


  getType: getType = (err) ->
    if isInternal(err) then 'internal' else (err.type or 'error')


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


  AutoAuthError: class AutoAuthError extends CordError
    name: 'AutoAuthError'


  ConfigError: class ConfigError extends CordError
    name: 'ConfigError'


  MustTransitPage: class MustTransitPage extends CordError
    ###
    This error should be thrown to force transition to specified page
    ###
    name: 'MustTransitPage'
    constructor: (@widget, @params) ->
      super("Transition to #{@widget} required!")


  ItemNotFound: class ItemNotFound extends CordError
    ###
    This class of errors throws when some registry can not found some element by name
    ###
    name: 'ItemNotFound'

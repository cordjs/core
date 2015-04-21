define ->
  ###
  Custom exception classes used in the framework's core
  ###

  WidgetDropped: class WidgetDropped extends Error
    constructor: (@message) ->
      @name = 'WidgetDropped'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)

  WidgetSentenced: class WidgetSentenced extends Error
    constructor: (@message, @type = 'notice') ->
      @name = 'WidgetSentenced'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  BehaviourCleaned: class BehaviourCleaned extends Error
    constructor: (@message) ->
      @name = 'BehaviourCleaned'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  WidgetParamsRace: class WidgetParamsRace extends Error
    constructor: (@message, @type = 'warning') ->
      @name = 'WidgetParamsRace'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  MustReloadPage: class MustReloadPage extends Error
    constructor: (@message) ->
      @name = 'MustReloadPage'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  MegaIdAuthFailed: class MegaIdAuthFailed extends Error
    constructor: (@message) ->
      @name = 'MegaIdAuthFailed'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  AuthError: class AuthError extends Error
    constructor: (@message) ->
      @name = 'AuthError'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  ConfigError: class ConfigError extends Error
    constructor: (@message) ->
      @name = 'ConfigError'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  MustTransitPage: class MustTransitPage extends Error
    ###
    This error should be thrown to force transition to specified page
    ###
    name: 'MustTransitPage'
    constructor: (@widget, @params) ->
      super("Transition to #{@widget} required!")

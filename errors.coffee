define ->
  ###
  Custom exception classes used in the framework's core
  ###

  WidgetDropped: class WidgetDropped extends Error
    constructor: (@message) ->
      @name = 'WidgetDropped'
      @isCordInternal = true
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)

  WidgetSentenced: class WidgetSentenced extends Error
    constructor: (@message, @type = 'notice') ->
      @name = 'WidgetSentenced'
      @isCordInternal = true
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  BehaviourCleaned: class BehaviourCleaned extends Error
    constructor: (@message) ->
      @name = 'BehaviourCleaned'
      @isCordInternal = true
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  WidgetParamsRace: class WidgetParamsRace extends Error
    constructor: (@message, @type = 'warning') ->
      @name = 'WidgetParamsRace'
      @isCordInternal = true
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  MustReloadPage: class MustReloadPage extends Error
    constructor: (@message) ->
      @name = 'MustReloadPage'
      @isCordInternal = true
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

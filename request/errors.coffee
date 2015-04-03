define ->
  Http: class Http extends Error
    # Abstract, should not be instantiated directly
    constructor: (@message) ->
      @name = 'Http'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  InvalidResponse: class InvalidResponse extends Http
    constructor: (@response) ->
      @name = 'InvalidResponse'
      Http.call(this, "#{@response.statusCode} #{@response.statusText}")
      Http.captureStackTrace?(this, arguments.callee)


  Network: class Network extends Http
    constructor: (@message) ->
      @name = 'Network'
      Http.call(this, @message)
      Http.captureStackTrace?(this, arguments.callee)


  Aborted: class Aborted extends Network
    constructor: (@message) ->
      @name = 'Aborted'
      Network.call(this, @message)
      Network.captureStackTrace?(this, arguments.callee)

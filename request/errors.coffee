define ->
  Http: class Http extends Error
    # Abstract, should not be instantiated directly
    constructor: (@message) ->
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)
      @name = 'Http'


  InvalidResponse: class InvalidResponse extends Http
    constructor: (@response) ->
      Http.call(this, "#{@response.statusCode} #{@response.statusText}")
      Http.captureStackTrace?(this, arguments.callee)
      @name = 'InvalidResponse'


  Network: class Network extends Http
    constructor: (@message) ->
      Http.call(this, @message)
      Http.captureStackTrace?(this, arguments.callee)
      @name = 'Network'


  Aborted: class Aborted extends Network
    constructor: (@message) ->
      Network.call(this, @message)
      Network.captureStackTrace?(this, arguments.callee)
      @name = 'Aborted'

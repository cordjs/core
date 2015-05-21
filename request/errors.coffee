define ['cord!errors'], (errors) ->

  Http: class Http extends errors.CordError
    name: 'Http'


  InvalidResponse: class InvalidResponse extends Http
    name: 'InvalidResponse'

    constructor: (@response) ->
      super("#{@response.statusCode} #{@response.statusText}")


  Network: class Network extends Http
    name: 'Network'


  Aborted: class Aborted extends Network
    name: 'Aborted'

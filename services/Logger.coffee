define [
  'cord!Console'
  'cord!errors'
], (_console, errors) ->
  ###
  Logger service. It uses global _console util to handle error messages and publishes it to the right container
  ###
  class Logger

    constructor: (@serviceContainer) ->


    publish: (topic, data) ->
      ###
      Publishes the message to the serviceContainer recipients
      ###
      @serviceContainer.getService('postal').then (postal) =>
        postal.publish topic, data
      .catchIf errors.ConfigError (e) =>
        _console.error("Could not publish error information on topic #{topic}. Postal service is not ready.")


    # Process logging functions by console with right publish functionality
    for method in ['log', 'warn', 'error', 'assertLazy', 'clear']
      do (method) =>
        @::[method] = (args...) ->
          _console.logAndPublish(method, args, => @publish)



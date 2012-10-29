define [
], ->

  class Utils

    @parseArguments = (args, map) ->
      stringArgument = ''
      objectArgument = {}
      functionArgument = null

      for argument in args
        stringArgument = argument if typeof argument == 'string'
        objectArgument = argument if typeof argument == 'object'
        functionArgument = argument if typeof argument == 'function'

      for key, type of map
        map[key] = stringArgument if type == 'string'
        map[key] = objectArgument if type == 'object'
        map[key] = functionArgument if type == 'function'

      map

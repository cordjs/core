define [
  'postal'
], (postal) ->

  class Postal
    ###
    Postal service for transmitting messages within one container
    ###

    constructor: (@serviceContainer) ->


    _addContainerChannel: (envelope) ->
      ###
      Signs envelope with current container uid
      @param Object envelope
      @return Object Modified envelope
      ###
      if not envelope.topic?
        envelope =
          topic: envelope
      envelope.topic += '@' + @serviceContainer.uid()
      envelope


    publish: (args...) ->
      ###
      Publishes message to specific container recipients
      @param args The same arguments as in Postal.publish
      ###
      if args.length == 1
        envelope = args[0]
      else if args.length == 2
        envelope =
          topic: args[0]
          data: args[1]

      envelope = @_addContainerChannel(envelope)
      postal.publish envelope.topic, envelope.data


    subscribe: (args...) ->
      ###
      Subscribes for specific container publishers
      @param args The same arguments as in Postal.subscribe
      ###
      if args.length == 1
        envelope = args[0]
      else if args.length == 2
        envelope =
          topic: args[0]
          callback: args[1]

      postal.subscribe @_addContainerChannel(envelope)

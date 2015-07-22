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
      envelope.channel = (envelope.channel or '') + '@' + @serviceContainer.uid()
      envelope


    publish: (args...) ->
      ###
      Publishes message to specific container recipients
      @param args The same arguments as in Postal.publish
      ###
      if args.length == 1
        envelope = args
      else if args.length == 2
        envelope =
          topic: args[0]
          data: args[1]

      postal.publish @_addContainerChannel(envelope)


    subscribe: (options) ->
      ###
      Subscribes for specific container publishers
      @param options The same options as in Postal.subscribe
      ###
      postal.subscribe @_addContainerChannel(options)

define [], ->

  class UserAgent

    @inject: ['userAgentText']


    constructor: ->
      @iOs = false


    calculate: ->
      @iOs = /(iPad|iPhone)/.test @userAgentText

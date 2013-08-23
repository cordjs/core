define [], ->

  class UserAgent

    @inject: ['userAgentText']

    # https://developer.mozilla.org/en-US/docs/Browser_detection_using_the_user_agent

    constructor: ->
      @iOs = false
      @firefox = false
      @safari = false
      @opera = false

      @agents = []


    calculate: ->
      @agents['iOs'] = @iOs = /(iPad|iPhone)/.test @userAgentText
      @agents['firefox'] = @firefox = /Firefox/.test @userAgentText
      @agents['safari'] = @safari = (/Safari/.test(@userAgentText) and not (/Chrome/.test(@userAgentText) or /Chromium/.test(@userAgentText)))
      @agents['opera'] = @opera = /Opera/.test @userAgentText


    toString: ->
      agentsString = ''
      for name, value of @agents
        agentsString += (name + ' ') if value

      agentsString

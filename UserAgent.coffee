define [], ->

  class UserAgent

    @inject: ['userAgentText']

    # https://developer.mozilla.org/en-US/docs/Browser_detection_using_the_user_agent

    constructor: ->
      @iOs = false
      @firefox = false


    calculate: ->
      @iOs = /(iPad|iPhone)/.test @userAgentText
      @firefox = /Firefox/.test @userAgentText

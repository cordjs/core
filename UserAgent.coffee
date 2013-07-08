define [], ->

  class UserAgent

    @inject: ['userAgentText']

    calculate: ->
      console.log 'calculate: ->', @userAgentText

      @appleMobole = '/(iPad|iPhone)/'.test userAgent.text

`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], ->

  '/tab:activeTabId':
    regex: false
    action: 'default'
    params:
      someParam: 11
#      activeTabId:
#        type: 'int'
#        validate: /\d+/

#  '/simple/:number':
#    widget: './simpleLayout/SimpleLayout'

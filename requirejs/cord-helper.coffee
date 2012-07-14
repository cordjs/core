`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [], () ->
  cord =

    getPathType: (type) ->
      paths =
        'cord-w': '/widgets/'
        'cord-t': '/widgets/'
      paths[type]

    getPath: (name, config, type) ->

      ## search cord!
      nameParts = name.split('!')
      name = nameParts.slice(1).join('!') if nameParts.length > 1

      ## search comma
      namePartsComma = name.split(',')
      if namePartsComma.length > 1
        name = namePartsComma.slice(0, 1).join()

#      nameParts = name.split '/'

      if name.substr(0, 1) is '/'
        name = "#{ config.paths.pathBundles }#{name}"

      switch type
        when 'cord-w', 'cord-t'
          widgetName = cord.getWidgetName name
          widgetName = cord.widgetName widgetName if type == 'cord-w'

          if name.indexOf '//' > 0
            name = "#{ name.replace "//", cord.getPathType type }/#{ widgetName }"

      if namePartsComma.length > 1
        name = name + namePartsComma.slice(1)

      name

    getWidgetName: (name) ->
      nameParts = name.split '/'
      nameParts[nameParts.length - 1]

    getBundleName: (name) ->

      nameParts = name.split '/'
      console.log nameParts
      console.log 'getBun: ', nameParts.slice( 0, nameParts.length - 1).join '/'
      nameParts

    widgetName: (widgetName) ->
      "#{ widgetName.charAt(0).toUpperCase() }#{ widgetName.slice(1) }"

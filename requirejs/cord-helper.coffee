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

      if name.substr(0, 2) is '//'
        name = "#{ config.paths.pathBundles }#{ config.paths.currentBundle }#{name}"

      else if name.substr(0, 1) is '/'
        name = "#{ config.paths.pathBundles }#{name}"

      switch type
        when 'cord-w', 'cord-t'
          widgetName = cord.getWidgetName name
          widgetName = cord.widgetName widgetName if type == 'cord-w'

          if type == 'cord-t' and name.split('.').pop().length <= 4
            widgetName = ''

          else
            widgetName = "/#{ widgetName }"

          if name.indexOf '//' > 0
            name = "#{ name.replace "//", cord.getPathType type }#{ widgetName }"

      if namePartsComma.length > 1
        name = name + namePartsComma.slice(1)

      name

    getWidgetName: (name) ->
      nameParts = name.split '/'
      nameParts[nameParts.length - 1]

    getPathToWidget: (name) ->
      name = "#{ name.replace "//", cord.getPathType 'cord-w' }/"
      nameParts = name.split '/'
      "#{ nameParts.slice( 0, nameParts.length - 1).join '/' }"

    getPathToBundle: (name) ->
      if parseInt(name.indexOf '//') > 0
        nameParts = name.split('//')
        name = nameParts.slice(0, 1).join( '//' )
      else
        nameParts = name.split('/')
        name = nameParts.slice(0, nameParts.length - 1).join '/'
      name

    widgetName: (widgetName) ->
      "#{ widgetName.charAt(0).toUpperCase() }#{ widgetName.slice(1) }"

    load: (name, req, onLoad, config) ->
      path = cord.getPath name, config
      onLoad path

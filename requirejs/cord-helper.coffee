define [], () ->
  currentBundle = '';
  currentConfig = {};

  cord =

    getPathType: (type) ->
      '/widgets/'
#      paths =
#        'cord-w': '/widgets/'
#        'cord-t': '/widgets/'
#      paths[type]

    getPath: (name, config, type) ->
      currentConfig = config if config?

      ## search cord!
      nameParts = name.split '!'
      name = nameParts.slice(1).join('!') if nameParts.length > 1

      nameParts = name.split '/'

      if nameParts.length is 1
        switch type
          when 'cord-w', 'cord-t', undefined
            name = "/cord/core/widgets/#{ name }"
          else
            name = "/cord/core/#{ name }"

      ## search comma
      # Делаем поиск запятой, после которой можно передать параметры
      namePartsComma = name.split ','
      if namePartsComma.length > 1
        name = namePartsComma.slice(0, 1).join()

      # Если путь начинается с //, автоматом строим полный путь к текущему бандлу
      if name.substr(0, 2) is '//'
        name = "#{ currentConfig.paths.pathBundles }#{ currentConfig.paths.currentBundle }#{ cord.getPathType type }#{ name.slice(2)  }"

      # Или если одинарная /, строим в ручную путь от папки с бандлами
      else if name.substr(0, 1) is '/'
        name = "#{ currentConfig.paths.pathBundles }#{name}"

      # Формирование пути
      switch type
        when 'cord-w', 'cord-t'
          widgetName = cord.getWidgetName name
          widgetName = cord.widgetName widgetName if type == 'cord-w'

          if type == 'cord-t' and name.split('.').pop().length <= 4
            widgetName = ''

          else
            widgetName = "/#{ widgetName }"

          name = "#{ name }#{ widgetName }"

      if parseInt(name.indexOf '//') > 0
        name = name.replace '//', cord.getPathType type

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
      nameParts = name.split('!')
      name = nameParts.slice(1).join('!') if nameParts.length > 1

      if parseInt(name.indexOf '//') > 0
        nameParts = name.split('//')
        name = nameParts.slice(0, 1).join( '//' )
      else
        nameParts = name.split('/')
        name = nameParts.slice(0, nameParts.length - 1).join '/'

      name

    getPathToCss: (path) ->
      path = cord.getPath path

      if path.substr(0, 2) is './'
        path = "/#{ path.slice(2) }"
      else
        path = "/#{ path }"

      path

    setCurrentBundle: (path, isChecked) ->
      currentBundle = if isChecked? then path else cord.getPathToBundle path
      require.config
        paths:
          'currentBundle': currentBundle

    getCurrentBundle: ->
      currentBundle

    widgetName: (widgetName) ->
      "#{ widgetName.charAt(0).toUpperCase() }#{ widgetName.slice(1) }"

    load: (name, req, onLoad, config) ->
      path = cord.getPath name, config
      onLoad path

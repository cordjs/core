define [
  'moment'
  'cord!isBrowser'
  'underscore'
], (moment, isBrowser, _) ->

  if isBrowser
    momentru = require ['moment-ru'], (ru) =>
      moment.lang 'ru'
    timezoneOffset = (new Date()).getTimezoneOffset()
  else
    moment.lang 'ru'


  class Utils

    @parseArguments: (args, map) ->
      stringArgument = ''
      objectArgument = {}
      functionArgument = null

      for argument in args
        stringArgument = argument if typeof argument == 'string'
        objectArgument = argument if typeof argument == 'object'
        functionArgument = argument if typeof argument == 'function'

      for key, type of map
        map[key] = stringArgument if type == 'string'
        map[key] = objectArgument if type == 'object'
        map[key] = functionArgument if type == 'function'

      map


    @morphology = (number, n0, n1, n2) ->
      if _.isArray(n0)
        n1 = n0[1]
        n2 = n0[2]
        n0 = n0[0]

      number = number % 100
      number = number % 10 if number > 19

      return n2 if number >= 2 and number <= 4
      return n1 if number == 1
      return n0


    @phoneNumberFormat = (number) ->
      if not number
        return ''

      if number.length == 7
        number = [
          number.substr(0,3)
          number.substr(3,2)
          number.substr(5,2)
        ].join '-'
      else if number.length == 6
        number = [
          number.substr(0,3)
          number.substr(3,3)
        ].join '-'
      number


    @escapeTags = (input) ->
      tags = 
        '&': '&amp;'
        '<': '&lt;'
        '>': '&gt;'
        
      source = String(input)
      source.replace /[&<>]/g, (tag) ->
        tags[tag] or tag
      
    

    @stripTags = (input, allowed) ->
      ###
        A JavaScript equivalent of PHP’s strip_tags
        http://phpjs.org/functions/strip_tags/
      ###

      input = '' if not input

      allowed = (((allowed || "") + "").toLowerCase().match(/<[a-z][a-z0-9]*>/g) || []).join('')
      tags = /<\/?([a-z][a-z0-9]*)\b[^>]*>/gi
      commentsAndPhpTags = /<!--[\s\S]*?-->|<\?(?:php)?[\s\S]*?\?>/gi
      input.replace(commentsAndPhpTags, '').replace tags, ($0, $1) ->
        if allowed.indexOf('<' + $1.toLowerCase() + '>') > -1
          return $0
        else
          return '';


    @getNameInitials = (name) ->
      if not name
        return ''
      nameSplited = name.split(' ')

      nameInitials = nameSplited[0].charAt(0).toUpperCase() + '.'
      nameInitials += nameSplited[1].charAt(0).toUpperCase() + '.' if nameSplited[1]
      nameInitials = nameInitials.replace /\-\./g, ''

      nameInitials


    #Smart divide array into two pieces, where first piece should contain at least minFirst, and second not less than minSecond
    @smartArraySlice = (inputArray, minFirst, minSecond) ->
      if (inputArray.length < minFirst + minSecond)
        return { first: inputArray, second: [] }
      else
        return { first: inputArray.slice(0, minFirst), second: inputArray.slice(minFirst) }


    @getCaretInElement = (el) ->
      return el.selectionStart if el.selectionStart

      if document.selection
        el.focus()

        r = document.selection.createRange()
        return 0 if r == null

        re = el.createTextRange()
        rc = re.duplicate()

        re.moveToBookmark(r.getBookmark())
        rc.setEndPoint('EndToStart', re)

        return rc.text.length

      return 0


    @validateEmail = (email) ->
      re = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
      re.test email


    @truncateFileName = (name, left, right, symbol = '...') ->
      if left + right + symbol.length < name.length
        name = name.substr(0, left) + symbol + name.substr(-right)

      name


    @getIconColorById = (id) ->
      id = parseInt(id)
      id = 0 if isNaN(id)
      colors = ['#A6E8C7', '#FFDE8F', '#A9E1F2', '#F1B8C9', '#C7C9FA', '#C3EDAE']
      return colors[id % colors.length];


    @fixFirefoxEventOffset = (event) ->
      event.offsetX = if event.offsetX then event.offsetX else event.originalEvent.layerX
      event.offsetY = if event.offsetY then event.offsetY else event.originalEvent.layerY
      return event


    @upperFirstChar = (text) ->
      text.substr(0, 1).toUpperCase() + text.substr(1)


    @lowerFirstChar = (text) ->
      text.substr(0, 1).toLowerCase() + text.substr(1)


    @splitCamelCase = (text) ->
      Utils.upperFirstChar(text).match(/[A-Z][a-z0-9]*/g)


    @detransliterate = (text) ->
      rus = "щ ш ч ц ю я ё ж ъ ы э а б в г д е з и й к л м н о п р с т у ф х ь".split(' ')
      eng = "shh sh ch cz yu ya yo zh `` y' e` a b v g d e z i y k l m n o p r s t u f h `".split(' ')

      for x in [0..rus.length - 1]
        text = text.split(eng[x]).join(rus[x])
        text = text.split(eng[x].toUpperCase()).join(rus[x].toUpperCase())

      text

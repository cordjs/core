define [
  'moment'
  'cord!isBrowser'
  'underscore'
], (moment, isBrowser, _) ->

  if isBrowser
    momentru = require ['moment-ru'], (ru) =>
      moment.lang 'ru'
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

    @monthFormat = (month) ->
      months =
        0:  'января'
        1:  'февраля'
        2:  'марта'
        3:  'апреля'
        4:  'мая'
        5:  'июня'
        6:  'июля'
        7:  'августа'
        8:  'сентября'
        9:  'октября'
        10: 'ноября'
        11: 'декабря'
      months[month]

    @dateFormat = (text, format = 'simple') ->
      return '' if !text

      now = moment()

      if text == 'now'
        date = now
      else
        date = moment(text, 'YYYY-MM-DD HH:mm:ss')

      # в идеале написать date.calendar()
      # дока http://momentjs.com/docs/

      daysDiff = (date.sod().toDate() - now.sod().toDate()) / 86400000

      date = date.toDate()
      now = now.toDate()

      detailed = format == 'detailed'
      minutes = date.getMinutes()
      hours = date.getHours()
      time = (if hours < 10 then '0' else '') + hours + ':' + (if minutes < 10 then '0' else '') + minutes
      
      ## Сегодня
      if date.getDate() == now.getDate() and date.getMonth() == now.getMonth() and date.getYear() == now.getYear()
          return 'сегодня' + (if detailed then (' в ' + time) else '')
      ## Вчера
      else if daysDiff == -1
        return 'вчера' + (if detailed then (' в ' + time) else '')
      ## Завтра
      else if daysDiff == 1
        return 'завтра' + (if detailed then (' в ' + time) else '')
      else
        ## но в этом году
        if date.getYear() == now.getYear()
          if detailed
            return date.getDate() + ' ' + Utils.monthFormat(date.getMonth()) + ' в ' + time
          else
            return date.getDate() + ' ' + Utils.monthFormat(date.getMonth())
        else
          if detailed
            return date.getDate() + ' ' + Utils.monthFormat(date.getMonth()) + ' ' + date.getFullYear() + ' в ' + time
          else
            return date.getDate() + ' ' + Utils.monthFormat(date.getMonth()) + ' ' + date.getFullYear()


    @dateDiffInDays = (date) ->
      today = new Date()
      date = new Date date

      seconds = ( date - today ) / 1000
      seconds / ( 60 * 60 * 24 )


    @getAgeByBirthday = (date) ->
      today = new Date()
      birthDate = new Date(date)
      years = today.getFullYear() - birthDate.getFullYear()
      months = today.getMonth() - birthDate.getMonth()
      if (months < 0) or (months == 0 and today.getDate() < birthDate.getDate())
        years--
      years


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
      colors = ['#A6E8C7', '#FFDE8F', '#A9E1F2', '#F1B8C9', '#C7C9FA', '#C3EDAE']
      return colors[id % colors.length];


    @fixFirefoxEventOffset = (event) ->
      event.offsetX = if event.offsetX then event.offsetX else event.originalEvent.layerX
      event.offsetY = if event.offsetY then event.offsetY else event.originalEvent.layerY
      return event

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

  class DateUtils

    constructor: (@container) ->
      if isBrowser
        @localOffset = (new Date()).getTimezoneOffset()
      else
        #try to determine timezone
        @container.eval 'cookie', (cookie) =>
          @localOffset = cookie.get 'timezoneOffset'
          if !@localOffset || isNaN(parseInt(@localOffset))
            @localOffset = (new Date()).getTimezoneOffset()


    monthFormat: (month) ->
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


    dateFormat: (text, format = 'simple') ->
      return '' if !text

      now = moment()

      if text == 'now'
        date = now
      else
        text += '00' if text.length - text.indexOf('+') == 3
        date = moment(text, 'YYYY-MM-DD HH:mm:ssZZ')
        #Correct timezone to user's one
        if !isBrowser
          realDate = date.toDate()
          backendOffset = realDate.getTimezoneOffset()
          date = moment(new Date( realDate.getTime() + backendOffset - @localOffset ))


      # в идеале написать date.calendar()
      # дока http://momentjs.com/docs/

      daysDiff = (moment(date).startOf('day').toDate() - moment(now).startOf('day').toDate()) / 86400000

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
            return date.getDate() + ' ' + @monthFormat(date.getMonth()) + ' в ' + time
          else
            return date.getDate() + ' ' + @monthFormat(date.getMonth())
        else
          if detailed
            return date.getDate() + ' ' + @monthFormat(date.getMonth()) + ' ' + date.getFullYear() + ' в ' + time
          else
            return date.getDate() + ' ' + @monthFormat(date.getMonth()) + ' ' + date.getFullYear()


    dateDiffInDays: (date1, date2 = new Date()) ->
      date1 = new Date date1
      date2 = new Date date2

      seconds = ( date1 - date2 ) / 1000
      seconds / ( 60 * 60 * 24 )


    getAgeByBirthday: (date) ->
      today = new Date()
      birthDate = new Date(date)
      years = today.getFullYear() - birthDate.getFullYear()
      months = today.getMonth() - birthDate.getMonth()
      if (months < 0) or (months == 0 and today.getDate() < birthDate.getDate())
        years--
      years

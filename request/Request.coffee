define [
  'cord!Utils'
  'underscore'
  'postal'
  'cord!utils/Future'
], (Utils, _, postal, Future) ->

  class Request

    METHODS: ['get', 'post', 'put', 'del']

    defaultOptions: {}


    constructor: (options) ->
      @options = _.extend({}, @defaultOptions, options)
      @[method] = @createMethod(method) for method in @METHODS


    createMethod: (method) ->
      ###
      Создание метода отправки данных
      @param String method - название нового метода
      @return Function
      ###
      (url, params, callback) => @send(method, url, params, callback)


    createResponse: (error, xhr) ->
      ###
      Преобразование ответа от сервера в объект Response
      @param Object|null error
      @param Object|null xhr
      @return Response
      ###
      throw new Error('Request::createResponse not implemented')


    getSender: ->
      ###
      Объект реализующй методы отправки данных на сервер
      @return Object
      ###
      throw new Error('Request::sender not implemented')


    send: (method, url, params = {}, callback) ->
      ###
      Позволяет отправить запрос на сервер и получить овтет
      @param String method - тип запроса (get|put|post|del|etc...)
      @param String url - Url-адресс запроса
      @param Object params - параметры запроса
      @param Function callback - обработчик результат запроса (этот параметр является устаревшим)
      @return Future
      ###
      if callback
        console.trace 'DEPRECATION WARNING: callback-style Request::send result is deprecated, use promise-style result instead!'

      method = @_normalizeMethodName(method)
      [url, options, requestCallback] = @_resolveRequestArguments(method, [url, _.clone(params), callback])
      startRequestTime = new Date() if global.config.debug.request

      promise = Future.single("BrowserRequest::send(#{method}, #{url})")
      sender = @getSender()
      sender[method] url, options, (error, xhr, body) =>
        if not error and xhr.statusCode >= 400
          error =
            statusCode: xhr.statusCode
            statusText: xhr.body._message

        response = @createResponse(error, xhr)

        if global.config.debug.request
          executionTime = (new Date() - startRequestTime) / 1000
          request = _.object(['method', 'url', 'params'], [method, url, params])
          @debugCompletedRequest(executionTime, request, response)

        response.completePromise(promise)
        requestCallback?(body, response.error)

      promise


    getExtendedRequestOptions: (method, params) ->
      ###
      Получение дополнительных параметров запроса
      @param String method - название метода
      @param Object params - переданные параметры запроса
      @return Object
      ###
      @options


    debugCompletedRequest: (executionTime, request, response) ->
      ###
      Обработчик результата запроса для отладки
      @param Float executionTime - время выполнения запроса
      @param Object request - объект содержащий в себе парамтеры запроса
      @param Response response - объект содержащий в себе парамтеры ответа сервера
      ###
      indexXDR = request.url.indexOf '/XDR/'
      url = request.url.slice(indexXDR + 5)
      url = url.replace(/(&|\?)?access_token=[^&]+/, '')

      params =
        method: request.method
        url: url
        seconds: executionTime

      tags = ['request', request.method]

      if global.config.debug.request == 'full'
        fullParams = requestParams: request.params
        fullParams['response'] = response.body if response.body
        params = _.extend({}, params, fullParams)

      if params.requestParams and _.isArray(request.params.__noLogParams)
        for param in request.params.__noLogParams when params.requestParams[param]
          params.requestParams[param] = '<HIDDEN>'

      if response.error
        tags.push('error')
        errorParams =
          requestParams: request.params
          errorCode: response.statusCode
          errorText: response.statusText

        params = _.extend({}, params, errorParams)

        response.error.__logTags = tags
        response.error.__logParams = params
      else
        postal.publish 'logger.log.publish',
          tags: tags
          params: params


    _normalizeMethodName: (method) ->
      ###
      Приводит переданное название метода в соответствие с требованиями запроса
      @param String method - название метода
      @return String
      ###
      method = method.toLowerCase()
      _console.warn('Unknown request method:' + method) if method not in @METHODS
      method = 'del' if method == 'delete'
      method


    _resolveRequestArguments: (method, rawData) ->
      ###
      Обрабатывает переданные аргументы в Request::send, валидирует их и добавляет дополнительные параметры
      @param String method - название метода
      @param Array rawData - необработанные данные (url, params, callback)
      @return Array [url, params, callback]
      ###
      {url, params, callback} = Utils.parseArguments rawData,
        url: 'string'
        params: 'object'
        callback: 'function'

      url ?= params.url
      callback ?= params.callback

      delete params.__noLogParams
      [url, @getExtendedRequestOptions(method, params), callback]

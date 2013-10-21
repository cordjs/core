define [
  'the-box'
  'cord!utils/Future'
  'underscore'
], (Container, Future, _) ->

  class ServiceContainer extends Container

    isDefined: (path) ->
      ###
      Is sevice defined
      @param string path - Service name
      @return bool
      ###
      key = '_box_' + @_resolve(path)
      !!@[key]


    reset: (path) ->
      ###
      Reset services
      ###
      p = @._resolve(path)
      @['_box_val_' + p] = null
      @


    getNames: ->
      ###
      Get all defined services
      @return array
      ###
      _.map _.filter(Object.keys(@), (key) ->
        key.indexOf('_box_') > -1 and key.indexOf('_box_val_') == -1
      ), (key) ->
        key.replace '_box_', ''


    injectServices: (target) ->
      ###
      Injects services from the service container into the given target object using @inject property of the object's
       class, containing array of service names need to be injected. Services are injected as a object properties with
       the relevant name.
      @param Object target the instance to be injected to
      @return Future completed when all services asyncronously loaded and assigned into the target object
      ###
      injectPromise = new Future('Container::injectServices')

      if target.constructor.inject
        if _.isFunction target.constructor.inject
          services = target.constructor.inject()
        else
          services = target.constructor.inject

        for serviceName in services
          do (serviceName) =>
            if @isDefined serviceName
              injectPromise.fork()
              try
                @eval serviceName, (service) ->
                  if global.config?.debug.service
                    _console.log "Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name } finished success"

                  target[serviceName] = service
                  injectPromise.resolve()
              catch e
                _console.error "Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name } fail: #{ e.message }"
                target[serviceName] = undefined
                injectPromise.resolve()
            else
              if global.config?.debug.service
                _console.warn "Container::injectServices #{ serviceName } for target #{ target.constructor.name } is not defined"

      injectPromise

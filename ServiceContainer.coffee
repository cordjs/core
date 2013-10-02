define [
  'the-box'
  'cord!utils/Future'
  'underscore'
  'cord!isBrowser'
], (Container, Future, _, isBrowser) ->

  Container::injectServices = (target) ->
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
        injectPromise.fork()
        do (serviceName) =>
          servicePromise = Future.single("Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name }")
          try
            @eval serviceName, (service) ->
              if global.config?.debug.service
                _console.log "Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name } finished success"

              target[serviceName] = service
              servicePromise.resolve()
              injectPromise.resolve()
          catch e
            if global.config?.debug.service
              _console.error "Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name } fail: #{ e.message }"

            servicePromise.reject()
            target[serviceName] = undefined
            injectPromise.resolve()

    injectPromise


  Container

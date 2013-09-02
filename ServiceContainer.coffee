define [
  'the-box'
  'cord!utils/Future'
  'underscore'
], (Container, Future, _) ->

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
          try
            servicePromise = new Future('Container::injectServices -> eval(' + serviceName + ')')
            servicePromise.fork()
            @eval serviceName, (service) ->
              target[serviceName] = service
              servicePromise.resolve()
              injectPromise.resolve()
          catch e
            _console.error e.message
            target[serviceName] = undefined
            injectPromise.resolve()

    injectPromise


  Container

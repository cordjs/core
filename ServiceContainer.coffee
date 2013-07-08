define [
  'the-box'
  'cord!utils/Future'
], (Container, Future) ->

  Container::injectServices = (target) ->
    ###
    Injects services from the service container into the given target object using @inject property of the object's
     class, containing array of service names need to be injected. Services are injected as a object properties with
     the relevant name.
    @param Object target the instance to be injected to
    @return Future completed when all services asyncronously loaded and assigned into the target object
    ###
    injectPromise = new Future

    if target.constructor.inject
      for serviceName in target.constructor.inject
        injectPromise.fork()
        do (serviceName) =>
          try
            @eval serviceName, (service) ->
              target[serviceName] = service
              injectPromise.resolve()
          catch e
            console.error "Error: ", e
            target[serviceName] = undefined
            injectPromise.resolve()

    injectPromise


  Container

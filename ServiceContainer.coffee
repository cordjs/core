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
      path = @_resolve(path)
      !!(@['_box_' + path] or  @['_box_val_' + path])


    reset: (path) ->
      ###
      Reset services
      ###
      p = @._resolve(path)
      @['_box_val_' + p] = null
      this


    getNames: ->
      ###
      Get all defined services
      @return array
      ###
      _.map _.filter(Object.keys(@), (key) ->
        key.indexOf('_box_') > -1 and key.indexOf('_box_val_') == -1
      ), (key) ->
        key.replace '_box_', ''


    getService: (serviceName) ->
      ###
      Returns service by it's name. Like `eval` but promise-like.
      @param {String} serviceName
      @return {Future[Any]}
      ###
      result = Future.single("ServiceContainer::getService(#{serviceName})")
      try
        @eval serviceName, (service) =>
          if service instanceof Error
            result.reject(service)
            @reset(serviceName)
          else
            result.resolve(service)
      catch err
        result.reject(err)
        @reset(serviceName)
      result


    injectServices: (target) ->
      ###
      Injects services from the service container into the given target object using @inject property of the object's
       class, containing array of service names need to be injected. Services are injected as a object properties with
       the relevant name.
      @param Object target the instance to be injected to
      @return Future completed when all services asyncronously loaded and assigned into the target object
      ###
      injectPromise = new Future("Container::injectServices(#{target.constructor.name})")

      if target.constructor.inject
        if _.isFunction target.constructor.inject
          services = target.constructor.inject()
        else
          services = target.constructor.inject

        injectService = (serviceAlias, serviceName) =>
          if @isDefined(serviceName)
            injectPromise.fork()
            try
              @eval serviceName, (service) =>
                if service instanceof Error
                  _console.error "Container::injectServices::eval(#{serviceName}) for target #{target.constructor.name}" +
                                 " failed with error: #{ service }", service
                  injectPromise.reject(service)
                  # resetting failed service to give it a chance next time (mainly for auth-related purposes)
                  @reset(serviceName)
                else
                  _console.log "Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name } finished success" if global.config?.debug.service

                  target[serviceAlias] = service
                  injectPromise.resolve()
            catch e
              _console.error "Container::injectServices -> eval(#{ serviceName }) for target #{ target.constructor.name } fail: #{ e.message }", e
              target[serviceAlias] = undefined
              injectPromise.reject(e)
              @reset(serviceName)
          else
            _console.warn "Container::injectServices #{ serviceName } for target #{ target.constructor.name } is not defined" if global.config?.debug.service

        if _.isArray services
          for serviceName in services
            injectService serviceName, serviceName
        else
          for serviceAlias, serviceName of services
            injectService serviceAlias, serviceName

      injectPromise


    autoStartServices: (services) ->
      ###
      Auto-starts services from the given list which has `autoStart` flag enabled.
      Returns immediately, doesn't wait for the services.
      @param {Object} services Service description map from the bundle configs.
      ###
      for serviceName, info of services when info.autoStart
        do (serviceName) =>
          @eval serviceName, (service) =>
            if service instanceof Error
              _console.warn "Container::autoStartServices::eval(#{serviceName}) " +
                             " failed with error: #{ service }", service
              # resetting failed service to give it a chance next time (mainly for auth-related purposes)
              @reset(serviceName)
      return



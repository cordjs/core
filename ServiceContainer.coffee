define [
  'the-box'
  'cord!errors'
  'cord!utils/Future'
  'underscore'
], (Container, errors, Future, _) ->

  class ServiceDefinition

    constructor: (@name, @deps, @factory, @container) ->



  class ServiceContainer # extends Container


    constructor: ->
      # registered definitions. Keys are name, values are instance of ServiceDefinition
      @definitions = {}
      # already resolved services. Keys are name of service
      @instances = {}
      # futures of already scheduled service factories. Keys are name, values are futures
      @pendingFactories = {}


    isDefined: (name) ->
      ###
      Is sevice defined
      @param string path - Service name
      @return bool
      ###
      _(@definitions).has(name) or _(@instances).has(name)


    reset: (name) ->
      ###
      Reset services
      ###
      delete @instances[name]
      if @pendingFactories[name]?.pending()
        @pendingFactories[name].reject(".reset(#{name}) was called inside service initialization process!")
      delete @pendingFactories[name]
      this


    set: (name, instance) ->
      @reset(name)
      @instances[name] = instance
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


    def: (name, deps, factory) ->
      ###
      Registers a new service definition in container
      ###
      if _.isFunction(deps) and factory == undefined
        factory = deps
        deps = []
      @definitions[name] = new ServiceDefinition(name, deps ? [], factory, this)


    eval: (name, readyCb) ->
      ###
      Evaluates a service, on ready call
      Deprecated, please use getService()!
      ###
      @getService(name)
        .then (instance) -> readyCb?(instance)


    getService: (name) ->
      ###
      Returns service by it's name. Like `eval` but promise-like.
      @param {String} serviceName
      @return {Future[Any]}
      ###
      result = Future.single("ServiceContainer::getService(#{name})")
      if _(@instances).has(name)
        result.resolve(@instances[name])
        return result
      else if not _(@pendingFactories).has(name)
        # Call a factory for a service
        if not _(@definitions).has(name)
          throw new Error("There is no registered definition for called service '#{name}'")

        def = @definitions[name]
        @pendingFactories[name] = Future.single("Factory of service #{name}")
        # Ensure, that all of dependencies are loaded before factory call
        Future.sequence(_.map(def.deps, (dep) => @getService(dep)), "Deps for `#{name}`")
          .then () =>
            # call a factory with 2 parameters, get & done. On done resolve a result.
            locked = false
            done = (err, instance) =>
              try
                throw new Error('Done was already called!') if locked
                locked = true
                if err?
                  throw err
                else if instance instanceof Error
                  throw instance
                else
                  @instances[name] = instance
                  @pendingFactories[name].resolve(instance)
              catch err
                @pendingFactories[name].reject(err)
            res = def.factory(@get, done)
            if def.factory.length < 2
              done(res)
          .catch (e) => @pendingFactories[name].reject(e)
      result.when(@pendingFactories[name])


    get: (name) =>
      ###
      Gets service in a synchronized mode. This method passed as `get` callback to factory of service def
      ###
      if not _(@instances).has(name)
        throw new Error("Service #{name} is not loaded yet. Do you forget to specify it in `deps` section?")
      @instances[name]


    injectServices: (target) ->
      ###
      Injects services from the service container into the given target object using @inject property of the object's
       class, containing array of service names need to be injected. Services are injected as a object properties with
       the relevant name.
      @param Object target the instance to be injected to
      @return Future completed when all services asyncronously loaded and assigned into the target object
      ###
      injectFutures = []

      if target.constructor.inject
        if _.isFunction target.constructor.inject
          services = target.constructor.inject()
        else
          services = target.constructor.inject

        injectService = (serviceAlias, serviceName) =>
          if @isDefined(serviceName)
            injectFuture = Future.single("Inject #{serviceAlias} to #{target.constructor.name}")
            injectFutures.push(injectFuture)
            injectFuture.when(
              @getService(serviceName)
                .then (service) => target[serviceAlias] = service
                .catch (e) =>
                  @reset(serviceName)
                  throw e
            )
          else
            _console.warn "Container::injectServices #{ serviceName } for target #{ target.constructor.name } is not defined" if global.config?.debug.service

        if _.isArray services
          for serviceName in services
            injectService serviceName, serviceName
        else
          for serviceAlias, serviceName of services
            injectService serviceAlias, serviceName


      Future.sequence(injectFutures, "Container::injectServices(#{target.constructor.name})")


    autoStartServices: (services) ->
      ###
      Auto-starts services from the given list which has `autoStart` flag enabled.
      Returns immediately, doesn't wait for the services.
      @param {Object} services Service description map from the bundle configs.
      ###
      for serviceName, info of services when info.autoStart
        do (serviceName) =>
          @getService(serviceName)
            .catch (error) =>
              if not (error instanceof errors.AuthError)
                _console.warn "Container::autoStartServices::getService(#{serviceName}) " +
                               " failed with error: #{ error }", error
              # resetting failed service to give it a chance next time (mainly for auth-related purposes)
              @reset(serviceName)
      return

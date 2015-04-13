define [
  'cord!errors'
  'cord!utils/Future'
  'underscore'
], (errors, Future, _) ->

  class ServiceDefinition

    constructor: (@name, @deps, @factory, @container) ->



  class ServiceContainer # extends Container

    constructor: ->
      # registered definitions. Keys are name, values are instance of ServiceDefinition
      @_definitions = {}
      # already resolved services. Keys are name of service
      @_instances = {}
      # futures of already scheduled service factories. Keys are name, values are futures
      @_pendingFactories = {}


    isDefined: (name) ->
      ###
      Is service defined
      @param string path - Service name
      @return bool
      ###
      _(@_definitions).has(name) or _(@_instances).has(name)


    reset: (name) ->
      ###
      Reset service.
      ###
      # reset pending service only after instantiation
      promise = Future.single("Reset of '#{name}'")
      if _(@_pendingFactories).has(name)
        @_pendingFactories[name].finally =>
          delete @_instances[name]
          delete @_pendingFactories[name]
          promise.resolve()
      else
        delete @_instances[name]
        promise.resolve()
      promise


    set: (name, instance) ->
      @reset(name)
      @_instances[name] = instance
      @_pendingFactories[name] = Future.resolved(instance)
      this


    getNames: ->
      ###
      Get all defined services
      @return array
      ###
      _.union(_(@_definitions).keys(), _(@_instances).keys())


    allInstances: ->
      ###
      This method returns map with all initialized instances. Name of services are in keys
      ###
      _.clone(@_instances)


    def: (name, deps, factory) ->
      ###
      Registers a new service definition in container
      ###
      if _.isFunction(deps) and factory == undefined
        factory = deps
        deps = []
      @_definitions[name] = new ServiceDefinition(name, deps ? [], factory, this)


    eval: (name, readyCb) ->
      ###
      Evaluates a service, on ready call
      Deprecated, please use getService()!
      ###
      @getService(name)
        .then (instance) ->
          readyCb?(instance)
          return # Avoid to possible Future result of readyCb
        .catch (e) -> throw new Error("Eval for service `#{name}` failed with #{e}")


    getService: (name) ->
      ###
      Returns service by it's name. Like `eval` but promise-like.
      @param {String} serviceName
      @return {Future[Any]}
      ###
      return @_pendingFactories[name].then() if _(@_pendingFactories).has(name)

      # Call a factory for a service
      if not _(@_definitions).has(name)
        return Future.rejected(new Error("There is no registered definition for called service '#{name}'"))

      def = @_definitions[name]
      @_pendingFactories[name] = Future.single("Factory of service #{name}")
      # Ensure, that all of dependencies are loaded before factory call
      Future.sequence(def.deps.map((dep) => @getService(dep)), "Deps for `#{name}`").then (services) =>
        # call a factory with 2 parameters, get & done. On done resolve a result.

        deps = _.object(def.deps, services)
        get = (name) ->
          if _(deps).has(name)
            deps[name]
          else
            throw new Error("Service #{name} is not loaded yet. Did you forget to specify it in `deps` section?")

        locked = false
        done = (err, instance) =>
          try
            throw new Error('Done was already called') if locked
            locked = true
            if err?
              throw err
            else if instance instanceof Error
              throw instance
            else
              @_instances[name] = instance
              @_pendingFactories[name].resolve(instance)
          catch err
            @_pendingFactories[name].reject(err)
          return # we should not return future from this callback!

        res =
          try
            def.factory(get, done)
          catch factoryError
            factoryError

        if res instanceof Error
          done(res)
        else if def.factory.length < 2
          if res instanceof Future
            res
              .then (instance) => done(null, instance)
              .catch (error) => done(error)
          else
            done(null, res)
      .catch (e) =>
        @_pendingFactories[name].reject(e)
        return # we should not return rejected future from this callback!

      @_pendingFactories[name].catch (e) =>
        # Remove rejected factory from map
        delete @_pendingFactories[name]
        throw e


    isReady: (name) ->
      _(@_instances).has(name)


    get: (name) =>
      ###
      Gets service in a synchronized mode. This method passed as `get` callback to factory of service def
      ###
      if not @isReady(name)
        throw new Error("Service #{name} is not loaded yet. Did you forget to specify it in `deps` section?")
      @_instances[name]


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
            injectFutures.push(
              @getService(serviceName)
                .then (service) =>
                  target[serviceAlias] = service
                  return
                .name("Inject #{serviceName} to #{target.constructor.name}")
            )
          else
            _console.warn "Container::injectServices #{ serviceName } for target #{ target.constructor.name } is not defined" if global.config?.debug.service

        if _.isArray services
          for serviceName in services
            injectService serviceName, serviceName
        else
          for serviceAlias, serviceName of services
            injectService serviceAlias, serviceName

      Future.sequence(injectFutures, "Container::injectServices(#{target.constructor.name})").map -> target


    autoStartServices: (services) ->
      ###
      Auto-starts services from the given list which has `autoStart` flag enabled.
      Returns immediately, doesn't wait for the services.
      @param {Object} services Service description map from the bundle configs.
      ###
      for serviceName, info of services when info.autoStart
        do (serviceName) =>
          @getService(serviceName).catch (error) ->
            if not (error instanceof errors.AuthError) and
               not (error instanceof errors.ConfigError)  # supress "no BACKEND_HOST" error
              _console.warn "Container::autoStartServices::getService(#{serviceName}) " +
                            " failed with error: ", error
      return

define [
  'cord!errors'
  'cord!utils/Future'
  'cord!services/Logger'
  'underscore'
], (errors, Future, Logger, _) ->

  class ServiceDefinition

    constructor: (@name, @deps, @factory, @serviceContainer) ->



  class ServiceContainer

    # unique identifier of the serviceContainer
    _uid = null

    constructor: ->
      # registered definitions. Keys are name, values are instance of ServiceDefinition
      @_definitions = {}
      # already resolved services. Keys are name of service
      @_instances = {}
      # futures of already scheduled service factories. Keys are name, values are futures
      @_pendingFactories = {}

      @logger = new Logger(this)
      @set 'logger', @logger


    isDefined: (name) ->
      ###
      Is service defined
      @param string path - Service name
      @return bool
      ###
      _(@_definitions).has(name) or _(@_instances).has(name)


    reset: (name, resetDependants = true) ->
      ###
      Reset service.
      @return {Future<undefined>}
      ###
      if @_instances[name] instanceof ServiceContainer
        return

      # reset pending service only after instantiation
      if _(@_pendingFactories).has(name)
        @_pendingFactories[name].clear()
        delete @_pendingFactories[name]

      delete @_instances[name]

      @resetDependants(name) if resetDependants
      Future.resolved()


    resetDependants: (name) ->
      ###
      Reset those who are dependant on this service
      @param string name - service name
      ###
      if not @_definitions[name]
        return

      for key, definition of @_definitions when name in definition.deps
        @reset(key)

      return


    clearServices: ->
      ###
      Clear and reset all services
      ###
      for serviceName in @getNames()
        if @isReady(serviceName)
          @getService(serviceName).then (service) ->
            service.clear?() if _.isObject(service)
        @reset(serviceName)


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
      Registers a new service definition in serviceContainer
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
      return @_pendingFactories[name] if _(@_pendingFactories).has(name)

      # Call a factory for a service
      if not _(@_definitions).has(name)
        return Future.rejected(new errors.ConfigError("There is no registered definition for called service '#{name}'"))

      def = @_definitions[name]
      localPendingFactoy = @_pendingFactories[name] = Future.single("Factory of service \"#{name}\"")

      # Ensure, that all of dependencies are loaded before factory call
      Future.all(def.deps.map((dep) => @getService(dep)), "Deps for `#{name}`").then (services) =>
        # call a factory with 2 parameters, get & done. On done resolve a result.

        deps = _.object(def.deps, services)
        get = (depName) ->
          if _(deps).has(depName)
            deps[depName]
          else
            throw new Error("Service #{depName} is not loaded yet. Did you forget to specify it in `deps` section of #{name}?")

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
              localPendingFactoy.resolve(instance)
          catch err
            localPendingFactoy.reject(err)
          return # we should not return future from this callback!

        res =
          try
            def.factory(get, done)
          catch factoryError
            factoryError

        if res instanceof Error
          done(res)
        else if def.factory.length < 2
          ###
          If function arguments length 1 or 0, it means that function does not uses done() function inside.
          In this case function creates service in sync mode, or returns Future object.
          ###
          if res instanceof Future
            res
              .then (instance) => done(null, instance)
              .catch (error) => done(error)
          else
            done(null, res)
      .catch (e) =>
        localPendingFactoy.reject(e)
        return # we should not return rejected future from this callback!

      localPendingFactoy.catch (e) =>
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
        throw new errors.ConfigError("Service #{name} is not loaded yet. Did you forget to specify it in `deps` section?")
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
                .nameSuffix("Inject #{serviceName} to #{target.constructor.name}")
            )
          else
            @logger.warn "Container::injectServices #{ serviceName } for target #{ target.constructor.name } is not defined" if global.config?.debug.service

        if _.isArray services
          for serviceName in services
            injectService serviceName, serviceName
        else
          for serviceAlias, serviceName of services
            injectService serviceAlias, serviceName

      Future.all(injectFutures, "Container::injectServices(#{target.constructor.name})").then -> target


    autoStartServices: (services) ->
      ###
      Auto-starts services from the given list which has `autoStart` flag enabled.
      Returns immediately, doesn't wait for the services.
      @param {Object} services Service description map from the bundle configs.
      ###
      for serviceName, info of services when info.autoStart
        do (serviceName) =>
          @getService(serviceName).catch (error) =>
            if not (error instanceof errors.AuthError) and
               not (error instanceof errors.ConfigError)  # supress "no BACKEND_HOST" error
              @logger.warn "Container::autoStartServices::getService(#{serviceName}) " +
                            " failed with error: ", error
      return


    uid: ->
      ###
      Unique identifier of this ServiceContainer
      @return string
      ###
      if not @_uid?
        @_uid = _.uniqueId()
      @_uid

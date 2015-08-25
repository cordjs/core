describe 'EventEmitterFuturized', ->

  EventEmitterFuturized = null
  Future = null

  before (done) ->
    requirejs [
      'cord!utils/EventEmitterFuturized'
      'cord!utils/Future'
    ], (_EventEmitterFuturized, _Future) ->
      EventEmitterFuturized = _EventEmitterFuturized
      Future = _Future
      done()

  describe '.on', ->

    it 'should return self instance', ->
      emitter = new EventEmitterFuturized
      assert(emitter == emitter.on('event', ->))

  describe '.emit', ->

    it 'should return Future on any call', ->
      emitter = new EventEmitterFuturized
      emitRes = emitter.emit('eventName')
      assert(emitRes instanceof Future)

    it 'should call subscriber', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.on('eventName', subscriberSpy)
      emitter.emit('eventName')
      assert(subscriberSpy.calledOnce)

    it 'should call subscriber twice if twice subscribed', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.on('eventName', subscriberSpy)
      emitter.on('eventName', subscriberSpy)
      emitter.emit('eventName')
      assert(subscriberSpy.calledTwice)

    it 'should bypass second argument to all subscribers', ->
      emitter = new EventEmitterFuturized
      subscriber = sinon.spy()
      params = {}
      emitter.on('e', subscriber)
      emitter.emit('e')
      assert(subscriber.calledWith())
      subscriber.reset()
      emitter.emit('e', params)
      assert(subscriber.calledWith(params))
      subscriber.reset()
      emitter.emit('e', params, params)
      assert(subscriber.calledWith(params))

    describe 'result Future', ->

      it 'should be resolved only after all subscribers executed', ->
        emitter = new EventEmitterFuturized
        s1 = sinon.spy()
        s2 = sinon.spy()
        s3 = sinon.spy()
        emitter.on('e', s1).on('e', s2).on('e', s3)
        emitter.emit('e').then ->
          assert(s1.calledOnce)
          assert(s2.calledOnce)
          assert(s3.calledOnce)

      it 'should be resolved only after all returned by subscribers Futures resolved', ->
        emitter = new EventEmitterFuturized
        p1 = Future.timeout(10)
        p2 = Future.timeout(10)
        p3 = Future.timeout(10)
        s1 = sinon.spy(-> p1)
        s2 = sinon.spy(-> p2)
        s3 = sinon.spy(-> p3)
        emitter.on('e', s1).on('e', s2).on('e', s3)
        emitter.emit('e').then ->
          assert(s1.calledOnce)
          assert(s2.calledOnce)
          assert(s3.calledOnce)
          assert(p1.isResolved())
          assert(p2.isResolved())
          assert(p3.isResolved())

      it 'should be rejected if any of callback throws an error', ->
        emitter = new EventEmitterFuturized
        error = new Error()
        s = sinon.spy(-> throw error)
        emitter.on('e', s)
        emitter.emit('e').then(
          -> throw new Error('Future should be rejected!')
          (e) -> assert(e == error)
        )

      it 'should be rejected only after all callbacks called', ->
        emitter = new EventEmitterFuturized
        error = new Error
        p1 = Future.timeout(10)
        p2 = Future.timeout(10).then -> throw error
        p3 = Future.timeout(10)
        s1 = sinon.spy(-> p1)
        s2 = sinon.spy(-> p2)
        s3 = sinon.spy(-> p3)
        emitter.on('e', s1).on('e', s2).on('e', s3)
        emitter.emit('e').then(
          -> throw new Error('Future should be rejected')
          (e) ->
            assert(s1.calledOnce)
            assert(s2.calledOnce)
            assert(s3.calledOnce)
            assert(p1.isResolved())
            assert(p2.isRejected())
            assert(p3.isResolved())
            assert(e == p2.reason())
        )

  describe '.once', ->

    it 'should return self instance', ->
      emitter = new EventEmitterFuturized
      assert(emitter == emitter.once('event', ->))

    it 'should call subscriber once', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.once('eventName', subscriberSpy)
      emitter.emit('eventName')
      emitter.emit('eventName')
      assert(subscriberSpy.calledOnce)

    it 'should call subscriber once for each .once call', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.once('eventName', subscriberSpy)
      emitter.once('eventName', subscriberSpy)
      emitter.emit('eventName')
      assert(subscriberSpy.calledTwice)

    it 'should call subscriber once for each .once call, and keep calling for .on call', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.once('eventName', subscriberSpy)
      emitter.once('eventName', subscriberSpy)
      emitter.on('eventName', subscriberSpy)
      emitter.emit('eventName')
      assert(3 == subscriberSpy.callCount)
      subscriberSpy.reset()
      emitter.emit('eventName')
      assert(subscriberSpy.calledOnce)
      subscriberSpy.reset()
      emitter.emit('eventName')
      assert(subscriberSpy.calledOnce)

  describe '.off', ->

    it 'should return self instance', ->
      emitter = new EventEmitterFuturized
      assert(emitter == emitter.off('event', ->))

    it 'should disable subscriber if called after emit', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.on('eventName', subscriberSpy)
      emitter.emit('eventName')
      emitter.off('eventName', subscriberSpy)
      emitter.emit('eventName')
      assert(subscriberSpy.calledOnce)

    it 'should disable subscriber if called before emit', ->
      emitter = new EventEmitterFuturized
      subscriber = ->
      subscriberSpy = sinon.spy(subscriber)
      emitter.on('eventName', subscriberSpy)
      emitter.off('eventName', subscriberSpy)
      emitter.emit('eventName')
      assert(not subscriberSpy.called)

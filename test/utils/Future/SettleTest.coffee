describe 'Future', ->

  Future = null

  before (done) ->
    requirejs [
      'cord!utils/Future'
    ], (_Future) ->
      Future = _Future
      done()

  describe '.settle', ->

    it 'should always return a Future', ->
      res = Future.settle()
      chai.should().exist(res)
      res.should.be.instanceOf(Future)
      res = Future.settle(Future.try(-> []))
      chai.should().exist(res)
      res.should.be.instanceOf(Future)
      res = Future.settle([])
      chai.should().exist(res)
      res.should.be.instanceOf(Future)
      res = Future.settle([1,2,3])
      chai.should().exist(res)
      res.should.be.instanceOf(Future)
      res = Future.settle([Future.try(-> 1), Future.try(-> 2)])
      chai.should().exist(res)
      res.should.be.instanceOf(Future)

    describe 'result future', ->

      it 'should have correct FutureInspection instances', ->
        error = new Error()
        input = [
          1
          Future.try -> 2
          Future.try -> throw error
          Future.timeout(0).then -> 3
          Future.timeout(10).then -> throw error
        ]
        expected = [
          1
          2
          error
          3
          error
        ]
        res = Future.settle(input)
        assert(res instanceof Future)
        res.then (result) ->
          assert(Array.isArray(result))
          assert(result.length == expected.length)
          for v, i in result
            assert(typeof v == 'object')
            assert(v.isResolved instanceof Function)
            assert(v.isPending instanceof Function)
            assert(v.isRejected instanceof Function)
            assert(v.value instanceof Function)
            assert(v.reason instanceof Function)
            assert(not v.isPending())
            if expected[i] instanceof Error
              assert(v.isRejected())
              assert(v.reason() == expected[i])
            else
              assert(v.isResolved())
              assert(v.value() == expected[i])

    it 'should wait until passed future is resolved', ->
      input = [
        1
        2
        3
      ]
      expected = [
        1
        2
        3
      ]
      Future.settle(Future.timeout(10).then -> input).then (result) ->
        assert(Array.isArray(result))
        assert(result.length == expected.length)
        for v,i in result
          assert(v.isResolved())
          assert(v.value() == expected[i])

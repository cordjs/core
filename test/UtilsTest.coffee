describe 'Utils', ->

  classes = {}

  before (done) ->
    requirejs ['cord!Utils'], (Utils) ->
      classes =
        Utils: Utils
      done()

  describe '.objectHash', ->

    it 'should return same value for same object', ->
      {Utils} = classes
      object = {}
      Utils.objectHash(object).should.be.equal(Utils.objectHash(object))

    it 'should return different value for different objects', ->
      {Utils} = classes
      object1 = {}
      object2 = {}
      Utils.objectHash(object1).should.not.be.equal(Utils.objectHash(object2))

    it 'should not be possible to change hash of object', ->
      {Utils} = classes
      object = {}
      initialHash = Utils.objectHash(object)
      delete object[':__hash_code__:']
      initialHash.should.be.equal(Utils.objectHash(object))
      object[':__hash_code__:'] = 'not_a_hash'
      initialHash.should.be.equal(Utils.objectHash(object))

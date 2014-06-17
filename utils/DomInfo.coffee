define [
  './Future'
], (Future) ->

  class DomInfo
    ###
    Special helper class to pass DOM node creation and insertion events (in form of future/promises) deep
     through the render tree. This is need because widgets often need to know when they are already in the DOM, but
     usually in that places the have no control over DOM creation and insertion, they only rendering text templates.
    ###

    _domRootPromise: null
    _showPromise: null


    constructor: (name = '') ->
      @_domRootPromise = Future.single("DomInfo::domRoot -> #{name}")
      @_showPromise = Future.single("DomInfo::_show -> #{name}")


    setDomRoot: (el) ->
      ###
      Pass newly created DOM element to the listeners.
      @param jQuery el
      ###
      @_domRootPromise.resolve(el)


    markShown: ->
      ###
      Inform listeners that the DOM-element is inserted into the main document's DOM tree.
      ###
      throw new Error("DOM root must be set before show!") if not @_domRootPromise.completed()
      @_showPromise.resolve()


    domRootCreated: -> @_domRootPromise


    domInserted: -> @_showPromise


    completeWith: (anotherDomInfo) ->
      ###
      Links this DOM info to the given one. So it will be marked as created and shown when the given DOM info will be
       marked
      @param DomInfo anotherDomInfo another DomInfo instance which completion should mean completion of this DOM info
      ###
      @_domRootPromise.when(anotherDomInfo.domRootCreated())
      @_showPromise.when(anotherDomInfo.domInserted())


    @fake: ->
      result = new DomInfo('fake')
      result._domRootPromise.reject("DOM root from fake DomInfo should not be used!")
      result.markShown()
      result

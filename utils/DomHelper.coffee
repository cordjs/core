define [
  'jquery'
  './browser/Defer'
  './Future'
], ($, Defer, Future) ->

  hasMutationObserver = window.MutationObserver?
  hasMutationEvents = window.MutationEvent? if not @hasMutationObserver # prevent browser deprecation warning


  domInserted = ($parentNode, $insertingNode) ->
    ###
    Returns Future that resolves when $insertingNode is completely inserted and shown in DOM into the $parentNode
    @param jQuery $parentNode
    @param jQuery $insertingNode
    @return Future[undefined]
    @todo correct polling fallback
    @todo support for inserting multiple nodes at once
    @todo maybe implement also using animationStart event (https://github.com/taylorhakes/onNodesInserted)
    ###
    parentNode = $parentNode[0]
    insertingNode = $insertingNode[0]
    if parentNode and insertingNode
      result = Future.single('domHelper::domInserted')
      if hasMutationObserver
        observer = new MutationObserver (mutations) ->
          for mRecord in mutations
            for node in mRecord.addedNodes
              if node == insertingNode
                result.resolve()
                observer.disconnect()
                break
            break if result.completed()
        observer.observe(parentNode, childList: true)
      else if hasMutationEvents
        $insertingNode.on 'DOMNodeInserted', (ev) ->
          if ev.target == insertingNode
            result.resolve()
            $insertingNode.off 'DOMNodeInserted'
      else
        # fallback to little timeout if non of the methods is supported
        # todo: should be replaced with accurate polling
        setTimeout ->
          result.resolve()
        , 200

      # debug problems: inform if insertion future is never completed
      debugTimeout = setTimeout ->
        if not result.completed()
          _console.error "domInserted isn't completed after 10 seconds!", $parentNode, $insertingNode
          result.reject(new Error("domInserted isn't completed in 10 seconds for #{$parentNode} -> #{$insertingNode}"))
      , 10000

      result.done -> clearTimeout(debugTimeout)
    else
      _console.error "Illegal arguments for domInserted:", $parentNode, $insertingNode
      Future.rejected(new Error("Illegal arguments for domInserted: #{parentNode}, #{insertingNode}"))



  insertHtml: (id, html, callback) ->
    ###
    Dynamically inserts innerHtml into the DOM node with given ID and invokes callback on actually completion of the
    insertion.
    @param string id target DOM node id
    @param string html html-text to be inserted
    @param Function callback callback, that will be called after completion
    @deprecated
    ###
    $el = $('#' + id)
    if $el.length == 1
      cnt = 0
      wait = (c) ->
        Defer.nextTick ->
          if c == cnt
            $el.off 'DOMNodeInserted'
            callback?()

      $el.on 'DOMNodeInserted', ->
        wait(++cnt)
      $el.html html
    else
      throw new Error("There is no DOM element with such id: [#{ id }]!")


  append: ($where, $what) ->
    ###
    Inserts `$what` DOM (jQuery) element into the end of the `$where` (parent) element.
    @return Future[undefined] when DOM is actually inserted (async)
    ###
    result = domInserted($where, $what)
    $where.append($what)
    result


  prepend: ($where, $what) ->
    ###
    Inserts `$what` DOM (jQuery) element into the beginning of the `$where` (parent) element.
    @return Future[undefined] when DOM is actually inserted (async)
    ###
    result = domInserted($where, $what)
    $where.prepend($what)
    result


  replace: ($where, $what) ->
    ###
    Replaces `$where` DOM (jQuery) element with the `$what` element.
    @return Future[undefined] when DOM is actually inserted (async)
    ###
    result = domInserted($where.parent(), $what)
    $where.replaceWith($what)
    result

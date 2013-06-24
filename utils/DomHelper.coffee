define [
  'jquery'
  './browser/Defer'
  './Future'
], ($, Defer, Future) ->

  class DomHelper

    @hasMutationEvents: window.MutationEvent?
    @hasMutationObserver: window.MutationObserver?

    @insertHtml: (id, html, callback) ->
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


    @replaceNode: ($old, $new) ->
      ###
      Replaces single node with ability to know when the new node is actually in the DOM
      @param jQuery $old which node to replace
      @param jQuery $new inserting node
      @return Future completed when new node is actually inserted into the DOM
      ###
      result = Future.single()
      newNode = $new[0]
      enableObserve = false
      if @hasMutationObserver
        observer = new MutationObserver (mutations) ->
          for mRecord in mutations
            for node in mRecord.addedNodes
              if node == newNode
                result.resolve()
                observer.disconnect()
                break
            break if result.completed()
        parent = $old.parent()[0]
        enableObserve = (parent and newNode)
        observer.observe(parent, childList: true) if enableObserve
      else if @hasMutationEvents
        enableObserve = true and newNode
        if enableObserve
          $new.on 'DOMNodeInserted', (ev) ->
            if ev.target == newNode
              result.resolve()
              $new.off 'DOMNodeInserted'

      $old.replaceWith($new)

      if not enableObserve
        # fallback to little timeout if non of the methods is supported
        setTimeout ->
          result.resolve()
        , 100
      else
        # debug problems: inform if insertion future is never completed
        setTimeout ->
          if not result.completed()
            console.error "replaceNode didn't completed after 10 seconds!", $old, $new
            #result.reject()
        , 10000

      result


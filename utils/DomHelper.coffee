define [
  'jquery'
  './browser/Defer'
], ($, Defer) ->

  class DomHelper

    @insertHtml: (id, html, callback) ->
      ###
      Dynamically inserts innerHtml into the DOM node with given ID and invokes callback on actually completion of the
      insertion.
      @param string id target DOM node id
      @param string html html-text to be inserted
      @param Function callback callback, that will be called after completion
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

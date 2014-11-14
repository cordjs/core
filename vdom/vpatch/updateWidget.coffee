define [
  '../vtree/vtree'
], (vtree) ->

  (a, b) ->
    if vtree.isWidget(a) and vtree.isWidget(b)
      if ('name' of a) and ('name' of b)
        a.id == b.id
      else
        a.init == b.init
    else
      false

define [
  '../vtree/vtree'
], (vtree) ->

  (a, b) ->
    if vtree.isAlienWidget(a) and vtree.isAlienWidget(b)
      if ('name' of a) and ('name' of b)
        a.id == b.id
      else
        a.init == b.init
    else
      false

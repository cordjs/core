define [
  './vtree'
], (vtree) ->

  handleThunk = (a, b) ->
    renderedA = a
    renderedB = b

    renderedB = renderThunk(b, a)  if vtree.isThunk(b)
    renderedA = renderThunk(a, null)  if vtree.isThunk(a)

    a: renderedA
    b: renderedB


  renderThunk = (thunk, previous) ->
    renderedThunk = thunk.vnode
    renderedThunk = thunk.vnode = thunk.render(previous)  if not renderedThunk

    if not (vtree.isVNode(renderedThunk) or vtree.isVText(renderedThunk) or vtree.isWidget(renderedThunk))
      throw new Error('thunk did not return a valid node')

    renderedThunk


  handleThunk

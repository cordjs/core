define ->

  # Maps a virtual DOM tree onto a real DOM tree in an efficient manner.
  # We don't want to read all of the DOM nodes in the tree so we use
  # the in-order tree indexing to eliminate recursion down certain branches.
  # We only recurse into a DOM node if we know that it contains a child of
  # interest.
  domIndex = (rootNode, tree, indices, nodes) ->
    if not (indices or indices.length == 0)
      {}
    else
      indices.sort ascending
      recurse rootNode, tree, indices, nodes, 0


  noChild = {}

  recurse = (rootNode, tree, indices, nodes, rootIndex) ->
    nodes or= {}
    if rootNode
      nodes[rootIndex] = rootNode  if indexInRange(indices, rootIndex, rootIndex)
      vChildren = tree.children
      if vChildren
        childNodes = rootNode.childNodes

        for child, i in vChildren
          rootIndex += 1
          vChild = child or noChild
          nextIndex = rootIndex + (vChild.count or 0)

          # skip recursion down the tree if there are no nodes down here
          recurse(childNodes[i], vChild, indices, nodes, rootIndex)  if indexInRange(indices, rootIndex, nextIndex)
          rootIndex = nextIndex
    nodes


  # Binary search for an index in the interval [left, right]
  indexInRange = (indices, left, right) ->
    return false  if indices.length == 0
    minIndex = 0
    maxIndex = indices.length - 1
    while minIndex <= maxIndex
      currentIndex = ((maxIndex + minIndex) / 2) >> 0
      currentItem = indices[currentIndex]
      if minIndex == maxIndex
        return currentItem >= left and currentItem <= right
      else if currentItem < left
        minIndex = currentIndex + 1
      else if currentItem > right
        maxIndex = currentIndex - 1
      else
        return true
    false


  ascending = (a, b) ->
    (if a > b then 1 else -1)


  domIndex

define [
  './domIndex'
  './patchOp'
  'underscore'
], (domIndex, patchOp, _) ->

  patch = (rootNode, patches) ->
    patchRecursive rootNode, patches


  patchRecursive = (rootNode, patches, renderOptions) ->
    indices = patchIndices(patches)
    return rootNode  if indices.length == 0
    index = domIndex(rootNode, patches.a, indices)
    ownerDocument = rootNode.ownerDocument
    if not renderOptions
      renderOptions = patch: patchRecursive
      renderOptions.document = ownerDocument  if ownerDocument != document

    for nodeIndex in indices
      rootNode = applyPatch(rootNode, index[nodeIndex], patches[nodeIndex], renderOptions)

    rootNode


  applyPatch = (rootNode, domNode, patchList, renderOptions) ->
    return rootNode  if not domNode
    newNode = undefined
    if _.isArray(patchList)
      for patch in patchList
        newNode = patchOp(patch, domNode, renderOptions)
        rootNode = newNode  if domNode == rootNode
    else
      newNode = patchOp(patchList, domNode, renderOptions)
      rootNode = newNode  if domNode == rootNode
    rootNode


  patchIndices = (patches) ->
    indices = []
    for key of patches
      indices.push(Number(key))  if key != 'a'
    indices


  patch

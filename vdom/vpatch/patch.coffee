define [
  './domIndex'
  './patchOp'
  'underscore'
], (domIndex, patchOp, _) ->

  patch = (rootNode, patches, widgetRepo) ->
    ###
    Updates the given DOM node according to the given virtual-dom patch
    @param {Node} rootNode - DOM node to which apply the patch
    @param {Object} patches - special object containing old VNode and patch-lists by node indexes
    @param {WidgetRepo} widgetRepo - widget repository service injected to support widget-related patch operations
    @return {Node} updated root DOM node
    ###
    ownerDocument = rootNode.ownerDocument
    renderOptions =
      patch: patchRecursive
      widgetRepo: widgetRepo
    renderOptions.document = ownerDocument  if ownerDocument != document

    patchRecursive(rootNode, patches, renderOptions)


  patchRecursive = (rootNode, patches, renderOptions) ->
    indices = patchIndices(patches)
    return rootNode  if indices.length == 0
    index = domIndex(rootNode, patches.a, indices)

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

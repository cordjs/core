define [
  './handleThunk'
  './VPatch'
  './vtree'
  'underscore'
], (handleThunk, VPatch, vtree, _) ->

  diff = (a, b) ->
    patch = a: a
    walk a, b, patch, 0
    patch


  walk = (a, b, patch, index) ->
    return  if a == b

    apply = patch[index]

    if vtree.isThunk(a) or vtree.isThunk(b)
      thunks a, b, patch, index
    if not b?
      apply = deepClearNodeState(a, patch, index)
      apply = appendPatch(apply, new VPatch(VPatch.REMOVE, a, b))
    else if vtree.isVNode(b)
      if vtree.isVNode(a)
        if a.tagName == b.tagName and a.namespace == b.namespace and a.key == b.key
          propsPatch = diffProps(a.properties, b.properties)
          apply = appendPatch(apply, new VPatch(VPatch.PROPS, a, propsPatch))  if propsPatch
          apply = diffChildren(a, b, patch, apply, index)
        else
          apply = deepClearNodeState(a, patch, index)
          apply = appendPatch(apply, new VPatch(VPatch.VNODE, a, b))
      else
        apply = deepClearNodeState(a, patch, index)
        apply = appendPatch(apply, new VPatch(VPatch.VNODE, a, b))
    else if vtree.isVText(b)
      if not vtree.isVText(a)
        apply = deepClearNodeState(a, patch, index)
        apply = appendPatch(apply, new VPatch(VPatch.VTEXT, a, b))
      else if a.text != b.text
        apply = appendPatch(apply, new VPatch(VPatch.VTEXT, a, b))
    else if vtree.isWidget(b)
      if vtree.isWidget(a)
        # widgets are comparable if they have same type and key (if set)
        if a.type == b.type and a.key == b.key
          # comparing properties
          b.widgetInstance = a.widgetInstance  # optimizing widget instance link detection
          propsPatch = diffProps(a.properties, b.properties, b.hooks)
          apply = appendPatch(apply, new VPatch(VPatch.WIDGET_PROPS, a, propsPatch))  if propsPatch
        else
          # otherwise just replace the old widget with the new one
          apply = appendPatch(apply, new VPatch(VPatch.DESTROY_WIDGET, a, null))
          apply = appendPatch(apply, new VPatch(VPatch.WIDGET, a, b))
      else
        # if old node is not widget then just create new widget and replace it
        apply = deepClearNodeState(a, patch, index)
        apply = appendPatch(apply, new VPatch(VPatch.WIDGET, a, b))
    else if vtree.isAlienWidget(b)
      apply = deepClearNodeState(a, patch, index)  if not vtree.isAlienWidget(a)
      apply = appendPatch(apply, new VPatch(VPatch.ALIEN_WIDGET, a, b))

    patch[index] = apply  if apply
    return


  diffProps = (a, b) ->
    result = undefined
    for aKey, aValue of a
      if not (aKey of b)
        result or= {}
        result[aKey] = undefined

      bValue = b[aKey]
      if aValue == bValue
        continue
      else if _.isObject(aValue) and _.isObject(bValue)
        if getPrototype(bValue) != getPrototype(aValue)
          result or= {}
          result[aKey] = bValue
        else if vtree.isHook(bValue)
           result or= {}
           result[aKey] = bValue
        else
          objectDiff = diffProps(aValue, bValue)
          if objectDiff
            result or= {}
            result[aKey] = objectDiff
      else if aValue != bValue
        result or= {}
        result[aKey] = bValue

    for bKey of b
      if not (bKey of a)
        result or= {}
        result[bKey] = b[bKey]

    result


  getPrototype = (value) ->
    if Object.getPrototypeOf
      Object.getPrototypeOf(value)
    else if value.__proto__
      value.__proto__
    else if value.constructor
      value.constructor::


  diffChildren = (a, b, patch, apply, index) ->
    aChildren = a.children
    orderedSet = reorder(aChildren, b.children)
    bChildren = orderedSet.children

    aLen = aChildren.length
    bLen = bChildren.length
    len = (if aLen > bLen then aLen else bLen)
    i = 0

    while i < len
      leftNode = aChildren[i]
      rightNode = bChildren[i]
      index += 1
      if not leftNode
        # Excess nodes in b need to be added
        apply = appendPatch(apply, new VPatch(VPatch.INSERT, null, rightNode))  if rightNode
      else
        walk leftNode, rightNode, patch, index

      index += leftNode.count  if vtree.isVNode(leftNode) and leftNode.count

      i++

    # Reorder nodes last
    apply = appendPatch(apply, new VPatch(VPatch.ORDER, a, orderedSet.moves))  if orderedSet.moves
    apply


  deepClearNodeState = (vNode, patch, index) ->
    ###
    Recursively searches vDom for widgets and alien widgets and appends patch commands
     to destroy them befor DOM node is removed.
    @param {VNode} vNode
    @param {Object} patch
    @param {number} index
    @return {Array.<VPatch>} patch-list for the given vNode
    ###
    if vtree.isWidget(vNode)
      patch[index] = appendPatch(
        patch[index]
        new VPatch(VPatch.DESTROY_WIDGET, vNode, null)
      )
    else if vtree.isAlienWidget(vNode)
      if typeof vNode.destroy == 'function'
        patch[index] = appendPatch(
          patch[index]
          new VPatch(VPatch.DESTROY_ALIEN_WIDGET, vNode, null)
        )
    else if vtree.isVNode(vNode) and (vNode.hasWidgets or vNode.hasAlienWidgets)
      childIndex = index
      for child in vNode.children
        childIndex += 1
        deepClearNodeState(child, patch, childIndex)
        childIndex += child.count  if vtree.isVNode(child) and child.count
    patch[index]


  thunks = (a, b, patch, index) ->
    ###
    Create a sub-patch for thunks
    ###
    nodes = handleThunk(a, b)
    thunkPatch = diff(nodes.a, nodes.b)
    patch[index] = new VPatch(VPatch.THUNK, null, thunkPatch)  if hasPatches(thunkPatch)
    return


  hasPatches = (patch) ->
    for index of patch
      return true  if index != 'a'
    false


  # Execute hooks when two nodes are identical
  hooks = (vNode, patch, index) ->
    if vtree.isVNode(vNode)
      patch[index] = new VPatch(VPatch.PROPS, vNode.hooks, vNode.hooks)  if vNode.hooks
      if vNode.descendantHooks
        for child in vNode.children
          index += 1
          hooks child, patch, index
          index += child.count  if vtree.isVNode(child) and child.count
    return


  # List diff, naive left to right reordering
  reorder = (aChildren, bChildren) ->
    # O(M) time, O(M) memory
    bChildIndex = keyIndex(bChildren)
    bKeys = bChildIndex.keys
    bFree = bChildIndex.free

    if bFree.length == bChildren.length
      return {
        children: bChildren
        moves: null
      }

    # O(N) time, O(N) memory
    aChildIndex = keyIndex(aChildren)
    aKeys = aChildIndex.keys
    aFree = aChildIndex.free

    if aFree.length == aChildren.length
      return {
        children: bChildren
        moves: null
      }

    # O(MAX(N, M)) memory
    newChildren = []

    freeIndex = 0
    freeCount = bFree.length
    deletedItems = 0

    # Iterate through a and match a node in b
    # O(N) time,
    for aItem, i in aChildren
      itemIndex = undefined

      if aItem.key
        if bKeys.hasOwnProperty(aItem.key)
          # Match up the old keys
          itemIndex = bKeys[aItem.key]
          newChildren.push(bChildren[itemIndex])
        else
          # Remove old keyed items
          itemIndex = i - deletedItems++
          newChildren.push(null)
      else
        # Match the item in a with the next free item in b
        if freeIndex < freeCount
          itemIndex = bFree[freeIndex++]
          newChildren.push(bChildren[itemIndex])
        else
          # There are no free items in b to match with
          # the free items in a, so the extra free nodes
          # are deleted.
          itemIndex = i - deletedItems++
          newChildren.push(null)

    lastFreeIndex =
      if freeIndex >= bFree.length
        bChildren.length
      else
        bFree[freeIndex]

    # Iterate through b and append any new keys
    # O(M) time
    for newItem, j in bChildren
      if newItem.key
        if not aKeys.hasOwnProperty(newItem.key)
          # Add any new keyed items
          # We are adding new items to the end and then sorting them
          # in place. In future we should insert new items in place.
          newChildren.push(newItem)
      else if j >= lastFreeIndex
        # Add any leftover non-keyed items
        newChildren.push(newItem)

    simulate = newChildren.slice()
    simulateIndex = 0
    removes = []
    inserts = []
    simulateItem

    k = 0
    while k < bChildren.length
      wantedItem = bChildren[k]
      simulateItem = simulate[simulateIndex]

      # remove items
      while simulateItem == null and simulate.length
        removes.push(remove(simulate, simulateIndex, null))
        simulateItem = simulate[simulateIndex]

      if not simulateItem or simulateItem.key != wantedItem.key
        # if we need a key in this position...
        if wantedItem.key
          if simulateItem and simulateItem.key
            # if an insert doesn't put this key in place, it needs to move
            if bKeys[simulateItem.key] != (k + 1)
              removes.push(remove(simulate, simulateIndex, simulateItem.key))
              simulateItem = simulate[simulateIndex]
              # if the remove didn't put the wanted item in place, we need to insert it
              if not simulateItem or simulateItem.key != wantedItem.key
                inserts.push({key: wantedItem.key, to: k})
              # items are matching, so skip ahead
              else
                simulateIndex++
            else
              inserts.push({key: wantedItem.key, to: k})
          else
            inserts.push({key: wantedItem.key, to: k})
          k++
        # a key in simulate has no matching wanted key, remove it
        else if simulateItem and simulateItem.key
          removes.push(remove(simulate, simulateIndex, simulateItem.key))
      else
        simulateIndex++
        k++

    # remove all the remaining nodes from simulate
    while simulateIndex < simulate.length
      simulateItem = simulate[simulateIndex]
      removes.push(remove(simulate, simulateIndex, simulateItem and simulateItem.key))

    # If the only moves we have are deletes then we can just
    # let the delete patch remove these items.
    if removes.length == deletedItems and not inserts.length
      children: newChildren
      moves: null
    else
      children: newChildren,
      moves:
        removes: removes,
        inserts: inserts


  remove = (arr, index, key) ->
    arr.splice(index, 1)

    from: index
    key: key


  keyIndex = (children) ->
    keys = {}
    free = []

    for child, i in children
      if child.key
        keys[child.key] = i
      else
        free.push(i)

    keys: keys     # A hash of key name to index
    free: free     # An array of unkeyed item indices


  appendPatch = (apply, patch) ->
    if apply
      if _.isArray(apply)
        apply.push(patch)
      else
        apply = [apply, patch]
      apply
    else
      patch



  diff

define [
  './applyProperties'
  './createElement'
  './domIndex'
  './updateAlienWidget'
  '../vtree/vtree'
], (applyProperties, createElement, domIndex, updateAlienWidget, vtree) ->

  class PatchScript
    ###
    Patch script - list of DOM manipulation commands to be executed later.
    The idea is firstly to asynchronously collect all DOM manipulation commands to be executed
     and then execute them synchronously by running the script.
    ###

    constructor: ->
      @_commands = []


    run: (rootNode) ->
      ###
      Executes the patch against actual DOM
      @param {Node} rootNode - root DOM node to run patch commands against
      @return {Node} updated root node after running the script
      ###
      executionContext =
        rootNode: rootNode
        currentNode: undefined
      runCommands(@_commands, executionContext)
      executionContext.rootNode


    runWithContext: (executionContext) ->
      ###
      Executes the patch script against the injected execution context.
      This method should only be used to run sub-scripts.
      @internal
      @param {Object} executionContext - execution context from the parent script
      ###
      runCommands(@_commands, executionContext)


    ## Script commands factory methods ##

    createDomIndex: (tree, indices) ->
      ###
      Adds command that creates DOM-index for the current DOM root and stores it in execution context
      @param {VNode} tree
      @param {Array.<number>} indices
      ###
      addScriptCommand(this, cmdCreateDomIndex, tree, indices)


    checkDomNode: (nodeIndex) ->
      ###
      Adds command that checks availability of the DOM node with the given node in the DOM index
       updates current DOM node in the execution context
       and interrupts script execution if the node is undefined.
      Only current subscript is interrupted.
      @param {number} nodeIndex
      ###
      addScriptCommand(this, cmdCheckDomNode, nodeIndex)


    createSubScript: ->
      ###
      Creates a new patch script and adds command to the current script to execute that sub-script.
      Useful when commands for the script are collected asyncrhonously but need to be executed in 'synchronous' order.
      @return {PatchScript}
      ###
      subScript = new PatchScript
      @runSubScript(subScript)
      subScript


    runSubScript: (subScript) ->
      ###
      Adds command to the current script to execute the given sub-script.
      Useful when commands for the script are collected asyncrhonously but need to be executed in 'synchronous' order.
      @param {PatchScript} subScript
      ###
      addScriptCommand(this, cmdRunSubScript, subScript)


    replaceNode: (newNode) ->
      ###
      Adds command that replaces current DOM node with the given one.
      @param {Node} newNode - pre-created new DOM node
      ###
      addScriptCommand(this, cmdReplaceNode, newNode)


    removeNode: ->
      ###
      Adds command that removes the current DOM node.
      ###
      addScriptCommand(this, cmdRemoveNode)


    appendChild: (newNode) ->
      ###
      Adds command that appends new child DOM node to the current DOM node.
      @param {Node} newNode
      ###
      addScriptCommand(this, cmdAppendChild, newNode)


    stringPatch: (vText, renderOptions) ->
      ###
      Adds command that updates text in current DOM node or replaces it with the text node.
      @param {VText} vText - vDom text node that should be rendered to real DOM
      @param {Object} renderOptions - auxiliary data need by vDom to DOM renderer
      ###
      addScriptCommand(this, cmdStringPatch, vText, renderOptions)


    applyProperties: (props, previous) ->
      ###
      Adds command that updates properties of the current DOM node according to the given old and new props of vNode.
      @param {Object} props - new props of the node
      @param {Object} previous - previous props of the node
      ###
      addScriptCommand(this, cmdApplyProperties, props, previous)


    reorderChildren: (bIndex) ->
      ###
      Adds command that reorders child nodes of the current DOM node
      @param {Array.<number>} bIndex - precomputed data about moving children around
      ###
      addScriptCommand(this, cmdReorderChildren, bIndex)


    updateWidgetProps: (props, widgetRepo) ->
      ###
      Adds command that updates properties of the current DOM node according to the given old and new props of vNode.
      @param {Object} props - new props of the node
      @param {WidgerRepo} widgetRepo - widget repository service
      ###
      addScriptCommand(this, cmdUpdateWidgetProps, props, widgetRepo)


    alienWidgetPatch: (leftVNode, alienWidget, renderOptions) ->
      ###
      Adds command that replaces current node with the alien widget or updates the existing alien widget
      @param {VNode} leftVNode - old vNode for the current DOM
      @param {AlienWidgetInterface} alienWidget - the target alien widget
      @param {Object} renderOptions - auxiliary data need by vDom to DOM renderer
      ###
      addScriptCommand(this, cmdAlienWidgetPatch, leftVNode, alienWidget, renderOptions)


    destroyAlienWidget: (vNode) ->
      ###
      Adds command that performs cleanup of the alien widget if the given vNode is alien widget
      @param {VNode} vNode - old vNode that should be cleaned if it's alien widget
      ###
      addScriptCommand(this, cmdDestroyAlienWidget, vNode)



  ## Possible DOM manipulation command codes ##

  cmdCreateDomIndex = 1
  cmdCheckDomNode = 2
  cmdReplaceNode = 10
  cmdRemoveNode = 11
  cmdAppendChild = 12
  cmdStringPatch = 13
  cmdApplyProperties = 14
  cmdReorderChildren = 15
  cmdUpdateWidgetProps = 20
  cmdAlienWidgetPatch = 30
  cmdDestroyAlienWidget = 31
  cmdRunSubScript = 99


  addScriptCommand = (patchScript, args...) ->
    ###
    Appends a new command to the patch-script.
    @param {PatchScript} patchScript
    @param {number} commandCode - one of possible DOM manipulation command codes (see above)
    @param {...*} args - arguments for the DOM manipulation command
    @return {PatchScript}
    ###
    patchScript._commands.push(args)
    patchScript


  runCommands = (commands, ec) ->
    ###
    Actually executes list of patch-script commands one by one.
    @param {Array.<Array>} commands - list of commands
    @param {Object} ec - execution context - structure shared between commands to store shared mutable execution state
    ###
    for cmd in commands
      switch cmd[0]
        when cmdRunSubScript then patchCommands.runSubScript(ec, cmd[1])
        when cmdCreateDomIndex then patchCommands.createDomIndex(ec, cmd[1], cmd[2])
        when cmdCheckDomNode
          break  if not patchCommands.checkDomNode(ec, cmd[1])

        when cmdReplaceNode then patchCommands.replaceNode(ec, cmd[1])
        when cmdRemoveNode then patchCommands.removeNode(ec)
        when cmdAppendChild then patchCommands.appendChild(ec, cmd[1])
        when cmdStringPatch then patchCommands.stringPatch(ec, cmd[1], cmd[2])
        when cmdApplyProperties then patchCommands.applyProperties(ec, cmd[1], cmd[2])
        when cmdReorderChildren then patchCommands.reorderChildren(ec, cmd[1])
        when cmdUpdateWidgetProps then patchCommands.updateWidgetProps(ec, cmd[1], cmd[2])
        when cmdAlienWidgetPatch then patchCommands.alienWidgetPatch(ec, cmd[1], cmd[2], cmd[3])
        when cmdDestroyAlienWidget then patchCommands.destroyAlienWidget(ec, cmd[1])
    return


  ## Actual DOM manipulation functions called when script is finally executed ##

  patchCommands =

    runSubScript: (ec, subScript) ->
      ###
      Executes sub-script with execution context of the current script.
      @param {Object} ec - execution context
      @param {PatchScript} subScript
      ###
      subScript.runWithContext(ec)


    createDomIndex: (ec, tree, indices) ->
      ###
      Creates DOM-index for the current DOM root and stores it in the execution context
      @param {Object} ec - execution context
      @param {VNode} tree - vdom tree matching the current DOM root element
      @param {Array.<number>} indices - list of patch keys (see patch.patchIndices)
      ###
      ec.domIndex = domIndex(ec.rootNode, tree, indices) # {Object.<number, Node>}
      return


    checkDomNode: (ec, nodeIndex) ->
      ###
      Updates current DOM node in the execution context according to the given index.
      Returns true if DOM node with the given index exists in previously created DOM-index
      @param {Object} ec - execution context
      @param {number} nodeIndex - index of the current node in the DOM-index
      @return {boolean}
      ###
      if ec.domIndex and ec.domIndex[nodeIndex]
        ec.currentNode = ec.domIndex[nodeIndex]
        true
      else
        false


    replaceNode: (ec, newNode) ->
      ###
      Replaces current DOM node with the given one.
      @param {Object} ec - script execution context
      @param {Node} newNode - DOM node to be injected instead of current node
      ###
      parentNode = ec.currentNode.parentNode
      parentNode.replaceChild(newNode, ec.currentNode)  if parentNode
      ec.rootNode = newNode  if ec.rootNode == ec.currentNode
      # ec.currentNode should not be updated (see `destroyAlienWidget`)
      return


    removeNode: (ec) ->
      ###
      Removes the current DOM node
      @param {Object} ec - execution context
      @todo add widget cleanup
      ###
      parentNode = ec.currentNode.parentNode
      parentNode.removeChild(ec.currentNode)  if parentNode
      ec.rootNode = null  if ec.rootNode == ec.currentNode
      return


    appendChild: (ec, newNode) ->
      ###
      Appends the given DOM node to the current DOM node
      @param {Object} ec - execution context
      @param {Node} newNode - pre-created DOM node to be appended
      ###
      ec.currentNode.appendChild(newNode)  if ec.currentNode
      return


    stringPatch: (ec, vText, renderOptions) ->
      ###
      Optimally modifies or replaces text node
      @param {Object} ec - execution context
      @param {VText} vText
      @param {Object} renderOptions
      ###
      domNode = ec.currentNode
      if domNode.nodeType == 3
        domNode.replaceData(0, domNode.length, vText.text)
      else
        newNode = createElement(vText, renderOptions) # this should always be synchronous
        @replaceNode(ec, newNode)
      return


    applyProperties: (ec, props, previous) ->
      ###
      Updates properties of the current DOM node according to the given changed props and old props.
      @param {Object} ec - execution context
      @param {Object} props - new props
      @param {Object} previous - old props
      ###
      applyProperties(ec.currentNode, props, previous)
      return


    reorderChildren: (ec, bIndex) ->
      ###
      Reorders child nodes of the current DOM node according to the given reorder data.
      @param {Object} ec - execution context
      @param {Array.<number>} bIndex - precomputed data about moving children around
      ###
      domNode = ec.currentNode
      children = []
      childNodes = domNode.childNodes
      reverseIndex = bIndex.reverse

      children.push(child) for child in childNodes

      insertOffset = 0
      move = undefined
      insertNode = undefined

      len = childNodes.length
      i = 0
      while i < len
        move = bIndex[i]
        if move != undefined and move != i
          # the element currently at this index will be moved later so increase the insert offset
          insertOffset++  if reverseIndex[i] > i

          node = children[move]
          insertNode = childNodes[i + insertOffset] or null
          domNode.insertBefore(node, insertNode)  if node != insertNode

          # the moved element came from the front of the array so reduce the insert offset
          insertOffset--  if move < i

        # element at this index == scheduled to be removed so increase insert offset
        insertOffset++  if i of bIndex.removes

        i++

      return


    updateWidgetProps: (ec, props, widgetRepo) ->
      ###
      Updates properties of the existing widget matching the current DOM node
      @param {Object} ec - execution context
      @param {Object} props - new props for the widget
      @param {WidgetRepo} widgetRepo - injected widget repository service to get widget instance by id
      ###
      debugger if not widgetRepo.getById(ec.currentNode.id)
      widgetRepo.getById(ec.currentNode.id).updateProps(props)
      return


    alienWidgetPatch: (ec, leftVNode, alienWidget, renderOptions) ->
      ###
      Replaces current DOM node with the alien widget or updates the existing alien widget
      @param {Object} ec - execution context
      @param {VNode} leftVNode - old vNode for the current DOM
      @param {AlienWidgetInterface} alienWidget - the target alien widget
      @param {Object} renderOptions - auxiliary data need by vDom to DOM renderer
      ###
      domNode = ec.currentNode
      if updateAlienWidget(leftVNode, alienWidget)
        newNode = alienWidget.update(leftVNode, domNode)
        ec.rootNode = newNode  if newNode and ec.rootNode == domNode
      else
        newWidget = createElement(alienWidget, renderOptions)
        @replaceNode(ec, newWidget)
        @destroyAlienWidget(ec, leftVNode)
      return


    destroyAlienWidget: (ec, w) ->
      ###
      Performs cleanup of the alien widget if the given vNode is alien widget
      @param {Object} ec - execution context
      @param {VNode|AlienWidgetInterface} w - potential alien widget node that should be destroyed
      ###
      w.destroy(ec.currentNode)  if typeof w.destroy == 'function' and vtree.isAlienWidget(w)
      return



  PatchScript

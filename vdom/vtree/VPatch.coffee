define ->

  VPatch = (type, vNode, patch) ->
    @type = Number(type)
    @vNode = vNode
    @patch = patch
    return


  VPatch.type = 'VPatch'

  VPatch.NONE = 0
  VPatch.VTEXT = 1
  VPatch.VNODE = 2
  VPatch.WIDGET = 3
  VPatch.PROPS = 4
  VPatch.ORDER = 5
  VPatch.INSERT = 6
  VPatch.REMOVE = 7
  VPatch.THUNK = 8


  VPatch

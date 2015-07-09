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
  VPatch.ALIEN_WIDGET = 3
  VPatch.PROPS = 4
  VPatch.ORDER = 5
  VPatch.INSERT = 6
  VPatch.REMOVE = 7
  VPatch.THUNK = 8
  VPatch.WIDGET = 9 # replace with widget or append widget
  VPatch.WIDGET_PROPS = 10 # update existing widget props
  VPatch.DESTROY_WIDGET = 11
  VPatch.DESTROY_ALIEN_WIDGET = 12


  VPatch

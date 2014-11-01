define ->

  isVNode: (x) ->
    x and x.constructor.type == 'VNode'


  isVText: (x) ->
    x and x.constructor.type == 'VText'


  isVHook: (hook) ->
    hook and typeof hook.hook == 'function' and not hook.hasOwnProperty('hook')


  isWidget: (w) ->
    w and w.type == 'Widget'


  isHook: (hook) ->
    hook and typeof hook.hook == 'function' and not hook.hasOwnProperty('hook')


  isThunk: (t) ->
    t and t.type == 'Thunk'

define [
  'cord!utils/profiler'
  'cord!Api'
  'cord!Widget'
  'cord!WidgetRepo'
  'cord!ServiceContainer'
  'cord!router/serverSideRouter'
  'dustjs-helpers'
], (pr, Api, Widget, WidgetRepo, ServiceContainer, router, dust) ->

  ->
    # zone-patching of cordjs higher-level functions which use asynchronous unpatched nodejs operations
    zone.constructor.patchFnWithCallbacks Api.prototype, [
      'send'
    ]

    pr.patch(Api.prototype, 'send', 1)
    pr.patch(Widget.prototype, 'renderTemplate', 1)
    pr.patch(Widget.prototype, 'resolveParamRefs', 1)
    pr.patch(WidgetRepo.prototype, 'createWidget', 0)
    pr.patch(ServiceContainer.prototype, 'injectServices', 0)
    pr.patch(dust, 'render', 0)
    pr.patch(router, 'process', 0, 'url')

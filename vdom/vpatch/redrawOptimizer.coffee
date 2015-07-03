define [
  'cord!utils/asapInContext'
  'cord!utils/Future'
], (asapInContext, Promise) ->

  redrawOptimizer =

    schedulePatch: (patchScript, rootNode) ->
      ###
      Adds the given patch-script to the queue for further batch-execution on upcoming requestAnimationFrame callback
      @param {PatchScript} patchScript
      @param {Node} rootNode
      @return {Promise.<undefined>} the promise will be fulfilled when the script is actually executed
      ###
      checkSchedule()
      patchQueue.push(patchScript)
      patchQueue.push(rootNode)
      flushPromise


  rafScheduled = false
  flushPromise = null
  patchQueue = null


  checkSchedule = ->
    ###
    Schedules requestAnimationFrame callback and sets internal variable when first patch arrives
    ###
    if not rafScheduled
      rafScheduled = true
      patchQueue = []
      flushPromise = Promise.single('redrawFlush')
      requestAnimationFrame(flushPatches)
    return


  flushPatches = ->
    ###
    Executes all scheduled patch-scripts and empties the queue for the next iteration.
    ###
    #console.log "raf", patchQueue

    runningPatchQueue = patchQueue
    runningFlushPromise = flushPromise

    rafScheduled = false
    patchQueue = null
    flushPromise = null

    len = runningPatchQueue.length
    index = 0
    while index < len
      # Advance the index before calling the task. This ensures that we will
      # begin flushing on the next task the task throws an error.
      runningPatchQueue[index].run(runningPatchQueue[index + 1])
      index += 2

    # using asap to avoid executing the promise callbacks in the context of current RAF and slow-down DOM repaint
    asapInContext(runningFlushPromise, runningFlushPromise.resolve)
    return


  redrawOptimizer

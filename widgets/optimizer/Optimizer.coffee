define [
  'cord!Widget'
  'fs'
  'underscore'
], (Widget, fs, _) ->

  class Optimizer extends Widget

    behaviourClass: false

    onShow: ->
      statFile = 'require-stat.json'
      @ctx.setDeferred 'optimizerMap'
      fs.readFile statFile, (err, data) =>
        stat = if err then {} else JSON.parse(data)
        @ctx.set optimizerMap: JSON.stringify(@generateOptimizationMap(stat), null, 2)


    _curStat: null


    generateOptimizationMap: (stat) ->
      map = @mapStat(stat)
      pageCount = Object.keys(stat).length
      console.log "pageCount", pageCount
      coreGroup = []
      countMap = {}
      for module, pages of map
        if pages.length == pageCount
          coreGroup.push(module)
        else if pages.length > 1
          countMap[module] = pages.length
      countMap

      resultGroups = [[pageCount, coreGroup]]

      @_curStat = stat
      remaining = Object.keys(countMap)

      while true
        newStat = {}
        for page, moduleList of @_curStat
          diff = _.difference(moduleList, coreGroup)
          if diff.length > 0
            newStat[page] = diff
        @_curStat = newStat

        groups = @calculateGroups(remaining)
        if groups.length and groups[0][1] > 1
          resultGroups.push([groups[0][0], groups[0][2]])
          remaining = _.difference(remaining, groups[0][2])
        else
          break

      resultGroups.push([0, remaining])

      resultGroups


    mapStat: (stat) ->
      result = {}
      for page, moduleList of stat
        for module in moduleList
          if module.indexOf('/bundles/cord/core/browserInit.js') == -1
            result[module] ?= []
            result[module].push(page)
      result


    calculateGroups: (moduleList) ->
      groups = []
      for item, i in moduleList
        groups = groups.concat(@collectGroups([item], moduleList, i))
      groups


    collectGroups: (prevGroup, list, startIndex) ->
      console.log "collectGroup", prevGroup
      result = []
      for i in [startIndex..list.length]
        group = prevGroup.concat([list[i]])
        if (cnt = @groupExists(group)) > 0
          result.push([cnt, cnt*group.length, group])
          result = result.concat(@collectGroups(group, list, i + 1))
      _.sortBy(result, (item) -> item[1]).reverse()


    groupExists: (group) ->
      count = 0
      for page, moduleList of @_curStat
        if _.intersection(moduleList, group).length == group.length
          count++
      count

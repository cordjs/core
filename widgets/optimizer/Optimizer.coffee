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
      resultGroups = []

      map = @mapStat(stat)

      @_countMap = {}
      onePageModules = {}
      twoPageModules = []
      sortList = []
      coreGroup = []
      pageCount = Object.keys(stat).length
      for module, pages of map
        matchCount = pages.length
        if matchCount == pageCount
          coreGroup.push(module)
        else if matchCount == 1
          onePageModules[pages[0]] ?= []
          onePageModules[pages[0]].push(module)
        else if matchCount == 2
          twoPageModules.push(module)
        else
          @_countMap[module] = pages.length
          sortList.push([module, pages.length])

      console.log "onePageModules(#{ onePageModules.length })", onePageModules
      console.log "twoPageModules(#{ twoPageModules.length })", twoPageModules

      sortList = _.sortBy sortList, (m) -> m[1]
      remaining = _.map sortList, (m) -> m[0]
      remaining = Object.keys(@_countMap).reverse()
      console.log "remainingCount = ", remaining.length

      resultGroups.push([pageCount, coreGroup]) if coreGroup.length


      @_curStat = {}
      for page, moduleList of stat
        @_curStat[page] = {}
        for module in moduleList
          @_curStat[page][module] = true

      console.log coreGroup.length, remaining.length

      groups = [[1, 1, coreGroup]]
      while true
        if groups.length
          for page, moduleMap of @_curStat
            @_curStat[page] = _.omit(moduleMap, groups[0][2])
            if Object.keys(@_curStat[page]).length == 0
              delete @_curStat[page]
        groups = @calculateGroups(remaining)
        if groups.length and groups[0][1] > 1
          remaining = _.difference(remaining, groups[0][2])
          remaining = (_.sortBy remaining, (m) => @_countMap[m]).reverse()
#          groups[0][2] = _.map groups[0][2], (m) => "#{m} --> #{@_countMap[m]}"
          resultGroups.push(groups[0])
        else
          break

      resultGroups.push([0, 0, remaining]) if remaining.length > 0

      console.log "\nCalculating one-page modules groups...\n"

      for page, modules of onePageModules
        resultGroups.push([1, modules.length, modules])

      console.log "Result: ", resultGroups

      resultGroups


    mapStat: (stat) ->
      result = {}
      for page, moduleList of stat
        for module in moduleList
          if module.indexOf('/bundles/cord/core/browserInit.js') == -1
            result[module] ?= []
            result[module].push(page)
      result


    _maxGroupScore: 0
    # time-point until which computation should continue.
    # When it's reached we just take the best result achieved at that moment
    _thresholdTime: 0

    calculateGroups: (moduleList) ->
      groups = []
      console.log "calculateGroups --> ", moduleList.length, (new Date).getTime()
      @_maxGroupScore = 0
      @_thresholdTime = (new Date).getTime() + 120000
      for item, i in moduleList
        groups = groups.concat(@collectGroups([], moduleList, i, Object.keys(@_curStat), 0))
        break if (new Date).getTime() >= @_thresholdTime
      _.sortBy(groups, (item) -> item[1]).reverse()


    collectGroups: (prevGroup, list, startIndex, checkPages, level) ->
      ###
      Recursive module group collector
      @param Array[String] prevGroup  accumulated on previous level existing group
      @param Array[String] list       source list of modules to process
      @param Int           startIndex which item of the list to start from (every recursive call must increase it)
      @param Array[String] checkPages short-list of pages to be used to check group existence (shortened by previous level)
      @param Int           level      nesting level for debugging
      @return Array[Array[(Int, Int, Array[String])]]
      ###
      result = []
      if (new Date).getTime() < @_thresholdTime
        for i in [startIndex..list.length]
          [cnt, matchPages] = @groupExists(list[i], checkPages)
          if cnt > 0
            group = prevGroup.concat([list[i]])

            # calculating score in a little complicated way
            # score is related to the group match count and size of the group, but when calculating size we take into
            # account only those modules whose individual occurences (in different pages) count is not far from
            # the weighted average module occurences count of the group
            scoreArr = _.map group, (m) => [m, @_countMap[m]]
            summ = _.reduce scoreArr, ((res, item) -> res + item[1]), 0
            avg = summ / group.length
            index = _.reduce scoreArr, (res, item) ->
              deviation = Math.abs(item[1] - avg)
              if deviation < res[0]
                [deviation, item[1]]
              else
                res
            , [2000000000, 0]
            scoreArr = _.filter scoreArr, (item) -> Math.abs(item[1] - index[1]) <= 1
            score = cnt * scoreArr.length
            # simple way: score = cnt * group.length

            if score > @_maxGroupScore
              result.push([cnt, score, group])
              @_maxGroupScore = score
              @_thresholdTime = (new Date).getTime() + 10000 # moving threshold ahead
              console.log "maxScore = ", score, group.length, (new Date).getTime()
            result = result.concat(@collectGroups(group, list, i + 1, matchPages, level + 1))
      result


    groupExists: (checkModule, checkPages) ->
      ###
      Returns count of pages in which the given module is used.
      @param String checkModule module to check
      @param Array[String] checkPages list of pages to check
      @return Int
      ###
      count = 0
      matchPages = []
      for page in checkPages
        if @_curStat[page][checkModule]
          count++
          matchPages.push(page)
      [count, matchPages]


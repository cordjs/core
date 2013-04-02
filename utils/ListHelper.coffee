define [
  'underscore'
], (_) ->

  class ListHelper

    @calculateTransitionCommands: (oldList, newList, options) ->
      ###
      Generates and returns list of abstract commands to convert old version of list to the new version.
      @param Array oldList the old list
      @param Array newList the new list
      @param Object options additional options to alter function behavour and resuls. Possible options:
                            * id - Function - which accepts the list items and returns it's unique id;
                                   String - name of the unique id field for the items;
                                   defaults to return item itself
                            * max - Integer - return false immediately if number of necessary commands exceeds this
                                    false - no limits
                                    default - false
                            * aggregate - Boolean - optimize number of commands by aggregating similar commands into one
                                          default - false
      @param (optional)String idField field name of the list items to uniquely identify fields
      @param (optional)Int maxCommands
      @return Array | false
      ###
      options ?= {}
      options.id ?= (item) -> item
      options.max ?= false
      options.aggregate ?= false

      result = []

      oldLength = oldList.length
      if oldLength
        if _.isFunction(options.id)
          id = options.id
        else
          id = (item) -> item[options.id]

        # build temporary reverse indexes to check existance
        oldReverse = {}
        oldReverse[id(item)] = true for item in oldList
        newReverse = {}
        newReverse[id(item)] = true for item in newList

        prevCommand = []
        collectResult = (command) ->
          if options.aggregate
            # if command doesn't match the previous command, then adding new
            if prevCommand[0] != command[0] \
                # moveBefore command can't be aggregated
                or command[0] == 'moveBefore' \
                # for insertBefore command beforeItem (third element) should match either
                or (command[0] == 'insertBefore' and prevCommand[2] != command[2])
              # converting to array (to arrgegate)
              command[1] = [command[1]] if command[0] != 'moveBefore'
              result.push(command)
              prevCommand = command
            else
              # if the previous command was the same, than just adding new item there (aggregating)
              prevCommand[1].push(command[1])
          else
            result.push(command)
          # checking options.max compliance and returning
          (options.max != false and result.length > options.max)


        # find out the first non-empty index of the old list
        for oldIndex of oldList
          break

        # find first element in oldList that exists in the newList
        # all non-existent elements are added to the result for removing
        while oldIndex < oldLength and not newReverse[(oldId = id(oldList[oldIndex]))]?
          result.push(['remove', oldList[oldIndex]])
          oldIndex++
        oldItem = oldList[oldIndex]

        movedIds = {}
        for newItem in newList
          if oldIndex < oldLength
            newId = id(newItem)
            # if models at current position of the lists doesn't match
            # current position of oldList is not moving forward in this case
            if newId != oldId
              # if the model with such id exists in the oldList at another position, adding move command
              if oldReverse[newId]?
                return false if collectResult(['moveBefore', newItem, oldItem])
                movedIds[newId] = true
              # if this is a new model, adding insert command
              else
                return false if collectResult(['insertBefore', newItem, oldItem])
            # if models match, moving position of the oldList forward
            else
              oldIndex++
              while oldIndex < oldLength
                oldItem = oldList[oldIndex]
                oldId = id(oldItem)
                # if the next model from the old list doesn't exists in the new one - adding remove command
                # and moving to the next position
                if not newReverse[oldId]?
                  return false if collectResult(['remove', oldItem])
                  oldIndex++
                # if the subsequent model was moved before, than just skipping it to the next position
                else if movedIds[oldId]?
                  oldIndex++
                else
                  break
          # if we already passed the whole old array, than all remaining models from the new array have to be appended
          # to the end
          else
            return false if collectResult(['append', newItem])
        result
      # if the old array is empty, than just adding append commands for every model of the new array
      else
        for item in newList
          return false if collectResult(['append', item])
        result

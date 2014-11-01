define ->

  classIdSplit = /([\.#]?[a-zA-Z0-9_:-]+)/
  notClassId = /^\.|#/

  (tag, props) ->
    return 'div'  if not tag

    noId = ('id' not of props)

    tagParts = tag.split(classIdSplit)
    tagName = null

    tagName = 'div'  if notClassId.test(tagParts[1])
    classes = null

    for part in tagParts
      continue  if not part

      type = part.charAt(0)

      if not tagName
        tagName = part
      else if type == '.'
        classes or= []
        classes.push(part.substring(1, part.length))
      else
        props.id = part.substring(1, part.length)  if type == '#' and noId

    if classes
      classes.push(props.className)  if props.className
      props.className = classes.join(' ')

    (if tagName then tagName.toLowerCase() else 'div')

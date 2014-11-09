define [
  '../vtree/vtree'
  'he'
], (vtree, he) ->

  encode = he.encode
#  validProps = require("./attributes")

  stringify = (node, parent) ->
    ###*
    Stringify given virtual dom tree and return html.
    @param {VirtualNode} node
    @param {VirtualNode?} parent
    @return {String}
    @api public
    ###
    return ''  if not node

    attributes = []
    html = []

    if vtree.isVNode(node)
      html.push('<' + node.tagName)

      for attrName, prop of node.properties
        # TODO: add smart logic about html attributes
        # https://github.com/facebook/react/blob/master/src/browser/ui/dom/HTMLDOMPropertyConfig.js
        attrVal = (if typeof prop == 'object' and attrName != 'style' then prop.value else prop)

        if attrVal
          # Set "class" attribute from "className" property.
          attrName = 'class'  if attrName == 'className' and not node.properties['class']

          # Special case for style. We need to iterate over all rules to create a
          # hash of applied css properties.
          if attrName == 'style'
            css = []
            css.push("#{styleProp}: #{styleVal};")  for styleProp, styleVal of attrVal
            attributes.push("#{attrName}=\"#{css.join(' ')}\"")
          else if attrVal == 'true' or attrVal == true
            attributes.push(attrName)
          else
            attributes.push("#{attrName}=\"#{encode(String(attrVal))}\"")

      html.push(' ' + attributes.join(' '))  if attributes.length
      html.push('>')

      if node.children and node.children.length
        html.push(stringify(child, node))  for child in node.children

      html.push("</#{node.tagName}>")

    else if vtree.isVText(node)
      if parent and parent.tagName == 'script'
        html.push(String(node.text))
      else
        html.push(encode(String(node.text)))

    html.join('')

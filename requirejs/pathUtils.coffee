`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define ->

  class PathUtils

    _publicPrefix: 'preved' # Medved

    setPublicPrefix: (prefix) ->
      @_publicPrefix = prefix

    getPublicPrefix: -> @_publicPrefix

    parsePathRaw: (path) ->
      ###
      Parses common cord's path format and returns structure with path parts information:
      ###

      canonicalDelimiter = '//'
      bundleSpec = null
      nameParts = path.split '@'
      throw new Error("Not more than one @ is allowed in the widget name specification: #{ path }!") if nameParts.length > 2
      if nameParts.length == 2
        bundleSpec = nameParts[1]
        throw new Error("Bundle specification should start with /: #{ path }") if bundleSpec.indexOf('/') != 0
        if bundleSpec.substr(-1) == '/'
          _console.warn "WARNING: trailing slash in bundle specification is deprecated: #{ path }! Cutting..."
          bundleSpec = bundleSpec.substr(0, bundleSpec.length - 1)
      path = nameParts[0]

      if path.indexOf('/') == -1
        bundleSpec = '/cord/core'
        relativePath = path
        canonicalDelimiter = '/'
      else
        nameParts = path.split '//'
        throw new Error("Not more than one // is allowed in widget name specification: #{ path }!") if nameParts.length > 2
        if nameParts.length == 2
          ns = nameParts[0]
          relativePath = nameParts[1]

          if ns.indexOf('/') == 0
            bundleSpec = ns
          else
            throw "Unknown bundle for widget: #{ path }" if not bundleSpec?
            if ns != ''
              bundleParts = bundleSpec.split '/'
              nsParts = ns.split '/'

              startJ = bundleParts.length - nsParts.length
              for i in [0..nsParts.length-1]
                bundleParts[startJ+i] = nsParts[i]

              bundleSpec = bundleParts.join '/'
        else
          canonicalDelimiter = '/'
          if path.substr(0, 7) == '/assets'
            if not bundleSpec?
              throw new Error("Bundle specification should be explicitly given when using \"/assets\" prefix!")
            relativePath = path.substr(1)
          else if path.substr(0, 1) == '/'
            if bundleSpec?
              if path.substr(0, bundleSpec.length) != bundleSpec
                throw new Error("Bundle specification doesn't match: " +
                  "[#{ path.substr(0, bundleSpec.length) } != #{ bundleSpec }]!")
              relativePath = path.substr(bundleSpec.length + 1)
            else
              throw new Error("Unsupported case: [#{ path }]! Need to implement considering " +
                'list of enabled bundles from application!')
          else
            bundleSpec = '/cord/core' if not bundleSpec?
            relativePath = path

      bundle: bundleSpec
      relativePath: relativePath
      delimiter: canonicalDelimiter


    convertCssPath: (path, context) ->
      ###
      Translates css path in cord's format in the context of the given file path of the calling css
      Used in pre-parsing stylus @import statements
      @param String path path in cord's format (may be not fully-qualified)
      @param String context relative or full path to the calling file
      @return String
      ###
      bundle = @extractBundleByFilePath context
      info = @parsePathRaw "#{ path }@#{ bundle }"

      # in case of css-import (using .css extension) result should be absolute url
      prefix = if path.substr(-4) == '.css' then '/' else 'public/'

      "#{ prefix }bundles#{ info.bundle }/widgets/#{ info.relativePath }"


    extractBundleByFilePath: (path) ->
      ###
      Extracts bundle specification from the module's file path
      @param String path fs path (absolute or relative) to the calling module's file
      @return String in form {{{/ns/../bundleName}}}
      ###
      bundleDir = 'bundles'
      start = path.indexOf bundleDir
      end = path.indexOf '/widgets'
      end = path.indexOf '/assets' if end == -1
      if start != -1 and end != -1 and start < end
        path.slice(start + bundleDir.length, end)
      else
        throw new Error("Can not extract bundle name from not-in-bundle file path: [#{ path }]!")



  new PathUtils

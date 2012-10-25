`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [],  ->
  dir = if window? then '' else './'
  class Config
    PUBLIC_PREFIX: 'preved'

    paths:

      'pathBundles':    dir + 'bundles'

      #plugins
      'text':           dir + 'vendor/requirejs/plugins/text'
      'cord-helper':    dir + 'bundles/cord/core/requirejs/cord-helper'
      'cord':           dir + 'bundles/cord/core/requirejs/cord'
      'cord-w':         dir + 'bundles/cord/core/requirejs/cord-w'
      'cord-t':         dir + 'bundles/cord/core/requirejs/cord-t'
      'cord-s':         dir + 'bundles/cord/core/requirejs/cord-s'

    parsePathRaw: (path) ->
      ###
      Parses common cord's path format and returns structure with path parts information:
      ###

      canonicalDelimiter = '//'
      bundleSpec = null
      nameParts = path.split '@'
      throw "Not more than one @ is allowed in the widget name specification: #{ path }!" if nameParts.length > 2
      if nameParts.length == 2
        bundleSpec = nameParts[1]
        throw "Bundle specification should start with /: #{ path }" if bundleSpec.indexOf('/') != 0
        if bundleSpec.substr(-1) == '/'
          console.warn "WARNING: trailing slash in bundle specification is deprecated: #{ path }! Cutting..."
          bundleSpec = bundleSpec.substr(0, bundleSpec.length - 1)
      path = nameParts[0]

      if path.indexOf('/') == -1
        bundleSpec = '/cord/core' if not bundleSpec?
        relativePath = path
        canonicalDelimiter = '/'
      else
        nameParts = path.split '//'
        throw "Not more than one // is allowed in widget name specification: #{ path }!" if nameParts.length > 2
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
            throw "Bundle specification should be explicitly given when using \"/assets\" prefix!" if not bundleSpec?
            relativePath = path.substr(1)
          else if path.substr(0, 1) == '/'
            if bundleSpec?
              throw "Bundle specification doesn't match: [#{ path.substr(0, bundleSpec.length) } != #{ bundleSpec }]!" if path.substr(0, bundleSpec.length) != bundleSpec
              relativePath = path.substr(bundleSpec.length + 1)
            else
              throw "Unsupported case! Need to implement considering list of enabled bundles from application!"
          else
            bundleSpec = '/cord/core' if not bundleSpec?
            relativePath = path

      bundle: bundleSpec
      relativePath: relativePath
      canonicalShortedPath: bundleSpec + canonicalDelimiter + relativePath


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
      "public/bundles#{ info.bundle }/widgets/#{ info.relativePath }"


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
        throw "Can not extract bundle name from not-in-bundle file path: [#{ path }]!"


  new Config

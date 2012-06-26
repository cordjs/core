require.config

  deps: ['widgetInitializer']

#  baseUrl: '/public'

  paths:
    'dustjs-linkedin': './vendor/dustjs/dust-amd-adapter',
    'jquery': './vendor/jquery/jquery-1.7.2.min',
    'underscore': './vendor/underscore/underscore-min',
    'requirejs': './vendor/requirejs/require',


require [
  'jquery'
], ($) ->


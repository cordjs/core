`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

#$(function() {
#
#});
#$ =>
#requirejs [
##  'cord-w!//Layout/Layout'
##  'cord-path!//tabContent'
##  'jquery'
#], (rr) ->
#  console.log '+++++++++++++++++++preloader: ', rr
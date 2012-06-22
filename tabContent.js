/**
 * Created with JetBrains PhpStorm.
 * User: davojan
 * Date: 20.05.12
 * Time: 12:56
 * To change this template use File | Settings | File Templates.
 */
//var dust = require('dustjs-linkedin')

if (typeof define !== 'function') { var define = require('amdefine')(module) }

define(['dustjs-linkedin'],
function (dust) {

  return {
    activeTab: 1,
    id: '',

    setActiveTab: function (tabId) {
      this.activeTab = tabId;
    },

    renderTemplate: function (callback) {
      var ctx = {
        activeTab: this.activeTab,
        id: this.id
      }
      dust.render('tabContent', ctx, callback);
    },

    renderClientSide: function (callback) {
//      var ctx = {
//        activeTab: this.activeTab,
//        id: this.id
//      }
//      dust.render('tabContent', ctx, callback);
    }
  };

});
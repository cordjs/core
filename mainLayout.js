/**
 * Created with JetBrains PhpStorm.
 * User: davojan
 * Date: 20.05.12
 * Time: 10:14
 * To change this template use File | Settings | File Templates.
 */

//var dust = require('dustjs-linkedin')

if (typeof define !== 'function') { var define = require('amdefine')(module) }

define(['dustjs-linkedin', './tabContent', 'postal'],
function (dust, tabContent, postal) {

  return {
    activeTab: 2,

    setActiveTab: function (tabId) {
      this.activeTab = tabId;

      tabContent.setActiveTab(tabId);

//      postal.publish({ topic: 'tabContent.changeTab', data: tabId });

      // прикидываемся, что у нас есть нормальная система событий
//      this.onTabChange();
    },

    show: function (params, callback) {
      this.setActiveTab(params.activeTabId);
      this.renderTemplate(callback);

//      var channel = postal.channel('default');
      postal.subscribe({ topic: '#.preved', callback: function() { console.log("preved medved!"); } })
      postal.publish({ topic: 'david.preved' });
    },

    onTabChange: function () {

    },

    renderTemplate: function (callback) {
      var ctx = {
        activeTab: this.activeTab,
        centralTabGroup: true,
        widget: function (chunk, context, bodies, params) {
          console.log(params)
          return chunk.map(function (chunk) {
            var widget = require('./' + params.name);
            widget.id = params.id;
            widget.renderTemplate(function (err, output) {
              if (err) throw err;
              chunk.end('<div id="' + params.id + '">' + output + '</div>')
            })
          });
        }
      }
      dust.render('mainLayout', ctx, callback);
    },

    setupBindings: function () {
      var self = this;
      $('#tab2').click(function (ev) {
        ev.preventDefault();
        self.setActiveTab(2);
        alert("hello! " + self.activeTab);
      })
    }
  }
});

// нужен универсальный event bus, который работает и на nodejs и в браузере
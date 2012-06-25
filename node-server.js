  /**
   * Created with JetBrains PhpStorm.
   * User: davojan
   * Date: 19.05.12
   * Time: 12:46
   * To change this template use File | Settings | File Templates.
   */

  var requirejs = require('requirejs');
  requirejs.config({
    nodeRequire: require
  });

  var http = require('http');
  var dust = require('dustjs-linkedin')
  var fs = require('fs')
  var static = require('node-static')
  var async = require('async')


  var file = new(static.Server)('./public/');

  http.createServer(function (req, res) {

    var url = require('url').parse(req.url)
    if (url.pathname === '/tab1') {

      var templates = [
        'public/mainLayout/mainLayout.html',
        'public/tabContent/tabContent.html',
        'public/tabContent/tab1Content.html',
        'public/tabContent/tab2Content.html'
      ];
      async.forEach(templates,
        // дело техники - компиляция и загрузка шаблонов
        function (file, callback) {
          fs.readFile(file, 'utf8', function (err, data) {
            if (err) callback(err);

            var split = file.split('.')[0].split('/');
            var name = split[split.length-1];

            dust.loadSource(dust.compile(data, name))
            callback(null)
          })
        },
        function (err) {
          if (err) throw err;
          res.writeHead(200, {'Content-Type': 'text/html'});

          var MainLayout = require('./public/mainLayout/MainLayout');
          var mainLayout = new MainLayout;
          require('./public/widgetInitializer').setRootWidget(mainLayout);

          mainLayout.show({activeTabId: 1}, function (err, output) {
            res.end(output)
          })
        }
      )
    }
    else if (url.pathname === '/tab2') {
      content = 'tab2\n'
      res.end(content);
    }
    else if (url.pathname === '/tab3') {
      content = 'tab3\n'
      res.end(content);
    }
    else if (url.pathname === '/simple') {
      fs.readFile('public/simpleLayout/simpleLayout.html', 'utf8', function (err, data) {
        if (err) callback(err)
        dust.loadSource(dust.compile(data, 'simpleLayout'));

        res.writeHead(200, {'Content-Type': 'text/html'});

        var SimpleLayout = require('./public/simpleLayout/SimpleLayout');
        var simpleLayout = new SimpleLayout;
        require('./public/widgetInitializer').setRootWidget(simpleLayout);
        simpleLayout.show({activeTabId: 1}, function (err, output) {
          res.end(output);
        });
      });
    }
    else {
      req.addListener('end', function () {
        file.serve(req, res)
      })
    }

  }).listen(1337, '127.0.0.1');
  console.log('Server running at http://127.0.0.1:1337/');
  console.log('Current directory: ' + process.cwd());
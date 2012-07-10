  /**
   * Created with JetBrains PhpStorm.
   * User: davojan
   * Date: 19.05.12
   * Time: 12:46
   * To change this template use File | Settings | File Templates.
   */

  var paths = require('./public/app/paths');
  requirejs = require('requirejs');
  requirejs.config({
    nodeRequire: require,
    baseUrl: 'public'
  });
  requirejs.config( paths );

  var http = require('http');
  var static = require('node-static');
  var router = require('./public/ServerSideRouter');

  router.addRoutes(require('./public/routes'));

  var file = new(static.Server)('./public/');

  http.createServer(function (req, res) {

    if (!router.process(req, res)) {
      req.addListener('end', function () {
        file.serve(req, res)
      });
    }

  }).listen(1337, '127.0.0.1');

  console.log('Server running at http://127.0.0.1:1337/');
  console.log('Current directory: ' + process.cwd());
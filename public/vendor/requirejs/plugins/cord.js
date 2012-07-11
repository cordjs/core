define(['module'], function (module) {
	'use strict';

//	console.log('first: ', arguments )

	var cord, type, moduleConfig;

//	console.log( 'mmmm:', arguments );

	type = module.id || 'cord';

	moduleConfig = {
		path: '/'
	};

	function checkPath ( path ) {
		if ( path.substr(0, 1) !== '/' ) {
			path = '/' + path;
		}
		return path;
	};

	function checkName ( name, config ) {
//		if ( name.substr(0, 2) == '//' ) {
//			name = './' + name.substr(2);
//		}
		var path = ( typeof config.paths.pathBundles !== "undefined" && config.paths.pathBundles !== null ? config.paths.pathBundles : '/' );
		path += checkPath( name );
		return path;
	};

	cord = {
		version: '1.0.0',

		load: function (name, req, onLoad, config) {
//			console.log ( 'loading...' )
			moduleConfig = moduleConfig || {};

//			if ( config.paths && config.paths.baseUrl ) {
//				moduleConfig.path = checkPath( config.paths.baseUrl );
//			}

//			console.log ('ssss', config.paths.cord )
//				console.log ( 'innnerReq: ', arguments )
//			console.log ( 'type:: ', type )
//			console.log ('nnnnnnaaaammmee:: ', name, checkName( name, config ))
			var path = checkName( name, config );

			console.log( name, config )

			switch ( type ) {
				case 'cord-t':
					path = 'text!' + path;
//					console.log( 'cord-t: path,   ', path )
					break;
				case 'cord-w':
					onLoad( {
						test: 'rrrr'
					} );
					return true;
					break;
			}

			req( [ path ], function ( data ) {
				if ( type == 'cord-t' ) {
					console.log( 'cord-t: data,   ' )
				}
//				console.log ( 'innnerReq: ', arguments )
				onLoad( data );
			} );
//			console.log( 'ddd: ', (moduleConfig.path + name) )
//			console.log( 'load: ', arguments )
//			onLoad({'a': 'b'});
		}
//		,
//		normalize: function () {
//			console.log( 'normalize', arguments )
//		}
	};

	return cord;
});

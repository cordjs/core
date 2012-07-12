define(['module'], function (module) {
	'use strict';
	var cord, moduleConfig;

	moduleConfig = {
		path: '/'
	};

	cord = {
		version: '1.0.0',

		checkName: function ( name, config ) {
			if ( name.substr(0, 2) == '//' ) {
				name = config.paths.ProjectNS + '/widgets/' + name.substr(2);
			}
			return name;
		},

		load: function (name, req, onLoad, config) {
			moduleConfig = moduleConfig || {};
			var path = cord.checkName( name, config );
			onLoad( path );
		}
	};

	return cord;
});

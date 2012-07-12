define(['module'], function (module) {
	'use strict';
	var cord;

//    console.log ( arguments )

	cord = {
		load: function (name, req, onLoad, config) {
            console.log ( '_____name', name )
			req( [ 'cord-path!' + name ], function ( path ) {
				req( [ path ], function ( data ) {
					onLoad( data );
				} );
			} );
		}
	};

	return cord;
});

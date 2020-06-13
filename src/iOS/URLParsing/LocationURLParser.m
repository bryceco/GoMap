//
//  GeoURLParser.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "LocationURLParser.h"
#import "MapView.h"


@implementation LocationURLParser

- (MapLocation *)parseURL:(NSURL *)url
{
    if ( [url.absoluteString hasPrefix:@"geo:"] ) {
        // geo:47.75538,-122.15979?z=18
        double lat = 0, lon = 0, zoom = 0;
        NSScanner * scanner = [NSScanner scannerWithString:url.absoluteString];
        [scanner scanString:@"geo:" intoString:NULL];
        if (![scanner scanDouble:&lat]) {
            /// Invalid latitude
            return nil;
        }
        [scanner scanString:@"," intoString:NULL];
        if (![scanner scanDouble:&lon]) {
            /// Invalid longitude
            return nil;
        }
        while ( [scanner scanString:@";" intoString:NULL] ) {
            NSMutableCharacterSet * nonSemicolon = [[NSCharacterSet characterSetWithCharactersInString:@";"] mutableCopy];
            [nonSemicolon invert];
            [scanner scanCharactersFromSet:nonSemicolon intoString:NULL];
        }
        if ( [scanner scanString:@"?" intoString:NULL] && [scanner scanString:@"z=" intoString:NULL] ) {
            [scanner scanDouble:&zoom];
        }
        
		MapLocation * parserResult = [MapLocation new];
		parserResult.longitude = lon;
		parserResult.latitude  = lat;
		parserResult.zoom      = zoom;
		parserResult.viewState = MAPVIEW_NONE;
		return parserResult;
	}

	if ( [url.absoluteString hasPrefix:@"gomaposm://?"] ) {
		BOOL hasCenter = NO, hasZoom = NO;
		double lat = 0, lon = 0, zoom = 0;
		MapViewState view = MAPVIEW_NONE;

		NSURLComponents * urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
		for ( NSURLQueryItem * queryItem in urlComponents.queryItems ) {

			if ( [queryItem.name isEqualToString:@"center"] ) {
				// scan center
				NSScanner * scanner = [NSScanner scannerWithString:queryItem.value];
				hasCenter = [scanner scanDouble:&lat] &&
							[scanner scanString:@"," intoString:NULL] &&
							[scanner scanDouble:&lon] &&
							scanner.isAtEnd;
			} else if ( [queryItem.name isEqualToString:@"zoom"] ) {
				// scan zoom
				NSScanner * scanner = [NSScanner scannerWithString:queryItem.value];
				hasZoom = [scanner scanDouble:&zoom] &&
							scanner.isAtEnd;
			} else if ( [queryItem.name isEqualToString:@"view"] ) {
				// scan view
				if ( [queryItem.value isEqualToString:@"aerial+editor"] ) {
					view = MAPVIEW_EDITORAERIAL;
				} else if ( [queryItem.value isEqualToString:@"aerial"] ) {
					view = MAPVIEW_AERIAL;
				} else if ( [queryItem.value isEqualToString:@"mapnik"] ) {
					view = MAPVIEW_MAPNIK;
				} else if ( [queryItem.value isEqualToString:@"editor"] ) {
					view = MAPVIEW_EDITOR;
				}
			} else {
				// unrecognized parameter
			}
		}
		if ( hasCenter ) {
			MapLocation * parserResult = [MapLocation new];
			parserResult.longitude = lon;
			parserResult.latitude  = lat;
			parserResult.zoom      = hasZoom ? zoom : 0.0;
			parserResult.viewState = view;
			return parserResult;
		}
	}
	return nil;
}

@end

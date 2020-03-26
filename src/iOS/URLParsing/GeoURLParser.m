//
//  GeoURLParser.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "GeoURLParser.h"
#import "URLParserResult.h"

@implementation GeoURLParser

- (URLParserResult *)parseURL:(NSURL *)url {
    URLParserResult *parserResult;
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
        
        parserResult = [[URLParserResult alloc] initWithLongitude:lon
                                                         latitude:lat
                                                             zoom:zoom
                                                        viewState:MAPVIEW_NONE];
    }
    
    return parserResult;
}

@end

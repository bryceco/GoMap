//
//  GeoURLParser.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@class URLParserResult;

NS_ASSUME_NONNULL_BEGIN

/// An object that parses `geo:` URLs
@interface GeoURLParser : NSObject

/// Attempts to parse the given URL.
/// @param url The URL to parse.
/// @return The parser result, if the URL was parsed successfully, or `nil` if the parser was not able to process the URL.
- (nullable URLParserResult *)parseURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END

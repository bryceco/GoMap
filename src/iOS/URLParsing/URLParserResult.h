//
//  URLParserResult.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MapView.h"

NS_ASSUME_NONNULL_BEGIN

/// An object that contains the result of the URL parser.
@interface URLParserResult : NSObject

- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                            zoom:(double)zoom
                       viewState:(MapViewState)viewState;

@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
@property (nonatomic, readonly) double zoom;
@property (nonatomic, readonly) MapViewState viewState;

@end

NS_ASSUME_NONNULL_END

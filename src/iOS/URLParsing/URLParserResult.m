//
//  URLParserResult.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "URLParserResult.h"

@implementation URLParserResult

- (instancetype)initWithLongitude:(double)longitude
                         latitude:(double)latitude
                             zoom:(double)zoom
                        viewState:(MapViewState)viewState{
    if (self = [super init]) {
        _longitude = longitude;
        _latitude = latitude;
        _zoom = zoom;
        _viewState = viewState;
    }
    
    return self;
}

@end

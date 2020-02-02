//
//  URLParserResult.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "URLParserResult.h"

@implementation URLParserResult

- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                            zoom:(double)zoom
                       viewState:(MapViewState)viewState{
    if (self = [super init]) {
        _latitude = latitude;
        _longitude = longitude;
        _zoom = zoom;
        _viewState = viewState;
    }
    
    return self;
}

@end

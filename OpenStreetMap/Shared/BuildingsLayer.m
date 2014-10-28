//
//  BuildingsLayer.m
//  Go Map!!
//
//  Created by Bryce on 10/27/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "BuildingsLayer.h"
#import "MapView.h"


@implementation BuildingsLayer

-(id)initWithMapView:(MapView *)mapView;
{
    self = [super init];
    if ( self ) {

	// observe changes to geometry
	_mapView = mapView;
	[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];

	self.opaque = NO;

	[self createObjects];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
    } else {
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


- (void)createObjects
{
}

@end

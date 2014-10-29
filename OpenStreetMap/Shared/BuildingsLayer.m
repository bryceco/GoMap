//
//  BuildingsLayer.m
//  Go Map!!
//
//  Created by Bryce on 10/27/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "BuildingsLayer.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmObjects.h"


@implementation BuildingsLayer

-(id)initWithMapView:(MapView *)mapView;
{
    self = [super init];
    if ( self ) {

		// observe changes to geometry
		_mapView = mapView;
		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];

		self.opaque = NO;

		[self getBuildings];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
		[self setNeedsLayout];
    } else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}



-(NSMutableArray *)getVisibleBuildings
{
    OSMRect box = [_mapView screenLongitudeLatitude];
    OsmMapData * mapData = _mapView.editorLayer.mapData;
    NSMutableArray * a = [NSMutableArray arrayWithCapacity:mapData.wayCount];
    [mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
		if ( obj.isShown == TRISTATE_YES ) {
			NSString * building = obj.tags[ @"building" ];
			if ( building ) {
				[a addObject:obj];
			}
		}
    }];
    return a;
}


-(NSArray *)layersForWay:(OsmWay *)way
{
	return nil;
}

-(void)layoutSublayers
{
#if 0
	self.sublayers = nil;

	NSArray * buildings = [self getVisibleBuildings];
	NSMutableArray * layers = [NSMutableArray new];
	for ( OsmBaseObject * object in buildings ) {
		if ( object.isWay ) {
			[layers addObjectsFromArray:[self layersForWay:object.isWay]];
		}
	}
	for ( CALayer * layer in layers ) {
		[self addSublayer:layer];
	}
#endif
}


- (void)getBuildings
{
    CALayer * layer1 = [CALayer new];
    layer1.backgroundColor = UIColor.redColor.CGColor;
    layer1.bounds = CGRectMake( 0, 0, 100, 100 );
    layer1.position = CGPointMake( 200, 200 );
    layer1.transform = CATransform3DMakeRotation( M_PI/4, 0, 1, 0);
    [self addSublayer:layer1];

    CALayer * layer2 = [CALayer new];
    layer2.backgroundColor = UIColor.greenColor.CGColor;
    layer2.bounds = CGRectMake( 0, 0, 100, 100 );
    layer2.position = CGPointMake( 300, 300 );
    layer2.transform = CATransform3DMakeRotation( -M_PI/4, 0, 1, 0);
    [self addSublayer:layer2];

    CATransform3D initialTransform = self.sublayerTransform;
    initialTransform.m34 = 1.0 / -500;
    self.sublayerTransform = initialTransform;
}

@end

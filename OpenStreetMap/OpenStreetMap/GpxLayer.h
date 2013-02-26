//
//  GpxLayer.h
//  OpenStreetMap
//
//  Created by Bryce on 2/22/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@class CLLocation;
@class MapView;


@interface GpxPoint : NSObject
@property (assign,nonatomic)	double		longitude;
@property (assign,nonatomic)	double		latitude;
@property (assign,nonatomic)	NSDate *	timestamp;
@end


@interface GpxLayer : CALayer
{
	MapView			*	_mapView;
	NSMutableArray *	_points;
}
@property (strong,nonatomic)	NSArray	*	points;
@property (assign,nonatomic)	BOOL		recording;


-(id)initWithMapView:(MapView *)mapView;
-(void)addPoint:(CLLocation *)location;

@end

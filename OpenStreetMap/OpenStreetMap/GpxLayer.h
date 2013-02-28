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
@property (assign,nonatomic)	double		elevation;
@property (assign,nonatomic)	NSDate *	timestamp;
@end

@interface GpxTrack : NSObject
@property (strong,nonatomic)	NSString	*	name;
@property (readonly,nonatomic)	NSArray		*	points;
@property (readonly,nonatomic)	NSDate		*	startDate;
@property (readonly,nonatomic)	NSTimeInterval	duration;
@property (readonly,nonatomic)	double			distance;

-(BOOL)saveXmlFile:(NSString * )path;
-(id)initWithXmlFile:(NSString * )path;
@end

@interface GpxLayer : CALayer
{
	MapView			*	_mapView;
}
@property (strong,nonatomic)	GpxTrack		*	activeTrack;
@property (strong,nonatomic)	NSMutableArray	*	previousTracks;

-(id)initWithMapView:(MapView *)mapView;
-(void)addPoint:(CLLocation *)location;

@end

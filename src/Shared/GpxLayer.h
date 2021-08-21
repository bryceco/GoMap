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
@property (strong,nonatomic)	NSDate *	timestamp;
@end

@interface GpxTrack : NSObject
{
	BOOL	_recording;
	double	_distance;
}
@property (strong,nonatomic)	NSString	*	name;
@property (readonly,nonatomic)	NSArray		*	points;

-(BOOL)saveXmlFile:(NSString * )path;
-(id)initWithXmlFile:(NSString * )path;

- (NSDate *)startDate;
- (NSTimeInterval)duration;
- (double)distance;

@end

@interface GpxLayer : CALayer
{
	MapView			*	_mapView;
}
@property (readonly,nonatomic)	GpxTrack		*	activeTrack;
@property (strong,nonatomic)	NSMutableArray	*	previousTracks;

-(id)initWithMapView:(MapView *)mapView;
-(void)addPoint:(CLLocation *)location;

-(void)startNewTrack;
-(void)endActiveTrack;

@end

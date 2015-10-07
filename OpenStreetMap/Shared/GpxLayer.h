//
//  GpxLayer.h
//  OpenStreetMap
//
//  Created by Bryce on 2/22/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#define USER_DEFAULTS_GPX_EXPIRATIION_KEY @"GpxTrackExpirationDays"


@class CLLocation;
@class MapView;


@interface GpxPoint : NSObject <NSCoding>
@property (assign,nonatomic)	double		longitude;
@property (assign,nonatomic)	double		latitude;
@property (assign,nonatomic)	double		accuracy;
@property (assign,nonatomic)	double		elevation;
@property (strong,nonatomic)	NSDate *	timestamp;
@end

@interface GpxTrack : NSObject <NSCoding>
{
	BOOL		_recording;
	double		_distance;
@public
	CGPathRef	shapePaths[20];
}
@property (strong,nonatomic)	NSString		*	name;
@property (strong,nonatomic)	NSDate			*	creationDate;	// when trace was recorded or downloaded
@property (readonly,nonatomic)	NSArray			*	points;
@property (strong,nonatomic)	CAShapeLayer	*	shapeLayer;

-(BOOL)saveXmlFile:(NSString * )path;
-(NSString *)gpxXmlString;
-(NSData *)gpxXmlData;
-(instancetype)initWithXmlData:(NSData *)data;
-(instancetype)initWithXmlFile:(NSString * )path;

- (NSTimeInterval)duration;
- (double)distance;

@end

@interface GpxLayer : CALayer
{
	MapView			*	_mapView;
	NSInteger			_stabilizingCount;
}
@property (readonly,nonatomic)	GpxTrack		*	activeTrack;
@property (strong,nonatomic)	NSMutableArray	*	previousTracks;

-(instancetype)initWithMapView:(MapView *)mapView;
-(void)addPoint:(CLLocation *)location;

-(void)loadTracksInBackgroundWithProgress:(void(^)(void))progressCallback;

-(void)startNewTrack;
-(void)endActiveTrack;
-(void)saveActiveTrack;
-(void)deleteTrack:(GpxTrack *)track;

-(void)trimTracksOlderThan:(NSDate *)date;

-(void)centerOnTrack:(GpxTrack *)track;

-(void)diskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount;
-(void)purgeTileCache;

-(BOOL)loadGPXData:(NSData *)data center:(BOOL)center;

@end

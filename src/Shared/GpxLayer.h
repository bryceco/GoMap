//
//  GpxLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 2/22/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#define USER_DEFAULTS_GPX_EXPIRATIION_KEY		 @"GpxTrackExpirationDays"
#define USER_DEFAULTS_GPX_BACKGROUND_TRACKING	 @"GpxTrackBackgroundTracking"


@class CLLocation;
@class MapView;


@interface GpxPoint : NSObject <NSCoding>
@property (assign,nonatomic)	double		longitude;
@property (assign,nonatomic)	double		latitude;
@property (assign,nonatomic)	double		accuracy;
@property (assign,nonatomic)	double		elevation;
@property (strong,nonatomic)	NSDate *_Nonnull	timestamp;
@end


@interface GpxTrack : NSObject <NSCoding>
{
	BOOL		_recording;
	double		_distance;
@public
	CGPathRef	shapePaths[20];	// an array of paths, each simplified according to zoom level so we have good performance when zoomed out
}
@property (strong,nonatomic)	NSString		*	name;
@property (strong,nonatomic)	NSDate			*	creationDate;	// when trace was recorded or downloaded
@property (nullable, readonly,nonatomic)	NSArray			*	points;
@property (strong,nonatomic)	CAShapeLayer	*	shapeLayer;

-(NSString *)gpxXmlString;
-(NSData *)gpxXmlData;
-(instancetype)initWithXmlData:(NSData *)data;
-(instancetype)initWithXmlFile:(NSString * )path;

-(NSTimeInterval)duration;
-(double)distance;

@end


@interface GpxLayer : CALayer
{
	MapView			*	_mapView;
	NSInteger			_stabilizingCount;
}
@property (readonly,nonatomic)	GpxTrack			*	activeTrack;		// track currently being recorded
@property (weak,nonatomic)		GpxTrack			*	selectedTrack;		// track picked in view controller
@property (strong,nonatomic)	NSMutableArray		*	previousTracks;		// sorted with most recent first
@property (readonly)			NSMutableDictionary	*	uploadedTracks;		// track name -> upload date


-(instancetype)initWithMapView:(MapView *)mapView;
-(void)addPoint:(CLLocation *)location;

-(void)loadTracksInBackgroundWithProgress:(void(^)(void))progressCallback;

-(void)startNewTrack;
-(void)endActiveTrack;
-(void)saveActiveTrack;
-(void)deleteTrack:(GpxTrack *)track;
-(void)markTrackUploaded:(GpxTrack *)track;

-(void)trimTracksOlderThan:(NSDate *)date;

-(void)centerOnTrack:(GpxTrack *)track;

-(void)getDiskCacheSize:(NSInteger *)pSize count:(NSInteger *)pCount;
-(void)purgeTileCache;

-(BOOL)loadGPXData:(NSData *)data center:(BOOL)center;

-(GpxTrack *)createGpxRect:(CGRect)rect;

@end

//
//  VoiceAnnouncement.h
//  Go Map!!
//
//  Created by Bryce on 10/26/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AVSpeechSynthesizer;
@class MapView;


@interface VoiceAnnouncement : NSObject
{
	AVSpeechSynthesizer *	_synthesizer;
	NSMutableDictionary *	_previousObjects;
	CLLocationCoordinate2D	_previousCoord;
	OsmWay				*	_currentHighway;
	OsmWay				*	_previousClosestHighway;

}

@property (assign,nonatomic)	MapView *	mapView;
@property (assign,nonatomic)	double		radius;

@property (assign,nonatomic)	BOOL		buildings;
@property (assign,nonatomic)	BOOL		streets;
@property (assign,nonatomic)	BOOL		addresses;
@property (assign,nonatomic)	BOOL		shopsAndAmenities;

@property (assign,nonatomic)	BOOL		enabled;

-(void)announceForLocation:(CLLocationCoordinate2D)coord;
@end

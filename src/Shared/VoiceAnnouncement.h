//
//  VoiceAnnouncement.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/26/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class MapView;


@interface VoiceAnnouncement : NSObject <AVSpeechSynthesizerDelegate>
{
	AVSpeechSynthesizer *	_synthesizer;
	NSMutableDictionary *	_previousObjects;
	CLLocationCoordinate2D	_previousCoord;
	OsmWay				*	_currentHighway;
	OsmWay				*	_previousClosestHighway;
	NSMapTable			*	_utteranceMap;

	BOOL					_isNewUpdate;
}

@property (assign,nonatomic)	MapView *	mapView;
@property (assign,nonatomic)	double		radius;

@property (assign,nonatomic)	BOOL		buildings;
@property (assign,nonatomic)	BOOL		streets;
@property (assign,nonatomic)	BOOL		addresses;
@property (assign,nonatomic)	BOOL		shopsAndAmenities;

@property (assign,nonatomic)	BOOL		enabled;

-(void)announceForLocation:(CLLocationCoordinate2D)coord;
-(void)removeAll;

@end

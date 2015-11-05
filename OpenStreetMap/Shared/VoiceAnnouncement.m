//
//  VoiceAnnouncement.m
//  Go Map!!
//
//  Created by Bryce on 10/26/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import "BingMapsGeometry.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "VoiceAnnouncement.h"


#import <AVFoundation/AVFoundation.h>


static inline OSMPoint OSMPointFromCoordinate( CLLocationCoordinate2D coord )
{
	OSMPoint point = { coord.longitude, coord.latitude };
	return point;
}

@implementation VoiceAnnouncement

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_utteranceMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaquePersonality valueOptions:NSPointerFunctionsOpaquePersonality];

		_buildings			= NO;
		_addresses			= NO;
		_streets			= YES;
		_shopsAndAmenities	= YES;

		_enabled			= YES;
	}
	return self;
}

-(void)say:(NSString *)text forObject:(OsmBaseObject *)object
{
	if ( _synthesizer == nil ) {
		_synthesizer = [[AVSpeechSynthesizer alloc] init];
		_synthesizer.delegate = self;
	}

	if ( object && _isNewUpdate ) {
		_isNewUpdate = NO;
		[self say:@"update" forObject:nil];
	}

	AVSpeechUtterance * utterance = [AVSpeechUtterance speechUtteranceWithString:text];
	[_synthesizer speakUtterance:utterance];

	[_utteranceMap setObject:object forKey:utterance];
}


-(void)removeAll
{
	[_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryWord];
	[_utteranceMap removeAllObjects];
}

-(void)setEnabled:(BOOL)enabled
{
	if ( enabled != _enabled ) {
		_enabled = enabled;
		if ( !enabled ) {
			[self removeAll];
		}
	}
}


-(void)announceForLocation:(CLLocationCoordinate2D)coord
{
	if ( !self.enabled )
		return;

	_isNewUpdate = YES;

	NSMutableArray * a = [NSMutableArray arrayWithCapacity:100];

	CGPoint metersPerDegree = { MetersPerDegreeLongitude(coord.latitude), MetersPerDegreeLatitude(coord.latitude) };
	if ( _previousCoord.latitude == 0 && _previousCoord.longitude == 0 )
		_previousCoord = coord;
	OSMRect box = { MIN(_previousCoord.longitude,coord.longitude), MIN(_previousCoord.latitude,coord.latitude), fabs(_previousCoord.longitude-coord.longitude), fabs(_previousCoord.latitude-coord.latitude) };
	box.origin.x -= _radius/metersPerDegree.x;
	box.origin.y -= _radius/metersPerDegree.y;
	box.size.width  += 2*_radius/metersPerDegree.x;
	box.size.height += 2*_radius/metersPerDegree.y;

	[self.mapView.editorLayer.mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
		if ( obj.deleted )
			return;
		if ( !obj.hasInterestingTags )
			return;
		// make sure it is within distance
		double dist = [obj distanceToLineSegment:OSMPointFromCoordinate(_previousCoord) point:OSMPointFromCoordinate(coord)];
		if ( dist < self.radius ) {
			[a addObject:@[ @(dist), obj ]];
		}
	}];

	// sort by distance
	[a sortedArrayUsingComparator:^NSComparisonResult(NSArray * obj1, NSArray * obj2) {
		double d1 = [obj1[0] doubleValue];
		double d2 = [obj2[0] doubleValue];
		return d1 < d2 ? NSOrderedAscending : d1 > d2 ? NSOrderedDescending : NSOrderedSame;
	}];

	NSDate * now = [NSDate new];
	NSMutableDictionary * currentObjects = [NSMutableDictionary new];
	OsmWay * closestHighwayWay  = nil;
	double	 closestHighwayDist = 1000000.0;
	OsmWay * newCurrentHighway = nil;
	for ( NSArray * item in a ) {
		OsmBaseObject * object	 = item[1];

		// track highway we're closest to
		if ( object.isWay && object.tags[@"highway"] ) {
			double	distance = [item[0] doubleValue];
			if ( distance < closestHighwayDist ) {
				closestHighwayDist = distance;
				closestHighwayWay  = object.isWay;
			}
		}
	}
	if ( closestHighwayWay && closestHighwayWay == _previousClosestHighway ) {
		if ( closestHighwayWay != _currentHighway ) {
			_currentHighway = closestHighwayWay;
			newCurrentHighway = _currentHighway;
		}
	}
	_previousClosestHighway = closestHighwayWay;

	for ( NSArray * item in a ) {
		OsmBaseObject * object	 = item[1];

		// if we've recently announced object then don't announce again
		NSNumber * ident = @(object.extendedIdentifier);
		currentObjects[ident] = now;
		if ( _previousObjects[ident] && object != newCurrentHighway )
			continue;

		if ( _buildings && object.tags[@"building"] ) {
			NSString * building = object.tags[@"building"];
			if ( [building isEqualToString:@"yes"] )
				building = @"";
			NSString * text = [NSString stringWithFormat:@"building %@",building];
			[self say:text forObject:object];
		}

		if ( _addresses && object.tags[@"addr:housenumber"] ) {
			NSString * number = object.tags[@"addr:housenumber"];
			NSString * street = object.tags[@"addr:street"];
			NSString * text = [NSString stringWithFormat:@"%@ number %@",street, number];
			[self say:text forObject:object];
		}
		
		if ( _streets && object.isWay && object.tags[@"highway"] ) {
			NSString * type = object.tags[@"highway"];
			NSString * name = object.tags[@"name"];
			if ( name == nil )
				name = object.tags[@"ref"];
			if ( [type isEqualToString:@"service"] && name == nil && object != newCurrentHighway ) {
				// skip
			} else {
				NSString * text = name ?: type;
				if ( object == newCurrentHighway )
					text = [NSString stringWithFormat:@"Now following %@",text];
				[self say:text forObject:object];
			}
		}
	
		if ( _shopsAndAmenities ) {
			if ( object.tags[@"shop"] || object.tags[@"amenity"] ) {
				NSString * text = object.friendlyDescription;
				[self say:text forObject:object];
			}
		}
	}

	_previousObjects = currentObjects;
	_previousCoord	= coord;
}

#pragma mark delegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance
{
	OsmBaseObject * object = [_utteranceMap objectForKey:utterance];
	_mapView.editorLayer.selectedNode		= object.isNode;
	_mapView.editorLayer.selectedWay		= object.isWay;
	_mapView.editorLayer.selectedRelation	= object.isRelation;
	[_utteranceMap removeObjectForKey:utterance];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance
{
	_mapView.editorLayer.selectedNode		= nil;
	_mapView.editorLayer.selectedWay		= nil;
	_mapView.editorLayer.selectedRelation	= nil;
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance
{
	[self speechSynthesizer:synthesizer didFinishSpeechUtterance:utterance];
}


@end

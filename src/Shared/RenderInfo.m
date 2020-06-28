//
//  RenderInfo.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "DLog.h"
#import "RenderInfo.h"

#if TARGET_OS_IPHONE
#include "DDXML.h"
#endif

@implementation RenderInfo

static RenderInfo * g_AddressRender = nil;
static RenderInfo * g_DefaultRender = nil;

-(NSString *)description
{
	return [NSString stringWithFormat:@"%@ %@=%@", [super description], _key, _value];
}

-(BOOL)isAddressPoint
{
	return self == g_AddressRender;
}


+(NSColor *)colorForHexString:(NSString *)text
{
	if ( text == nil )
		return nil;
	assert( text.length == 6 );
	int r = 0, g = 0, b = 0;
	assert( sscanf( text.UTF8String, "%2x%2x%2x", &r, &g, &b) == 3 );
#if TARGET_OS_IPHONE
	return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
#else
	return [NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
#endif
}



-(NSInteger)renderPriorityForObject:(OsmBaseObject *)object
{
	static NSDictionary * highwayDict = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		highwayDict = @{
			@"motorway"			: @29,
			@"trunk"			: @28,
			@"motorway_link"	: @27,
			@"primary"			: @26,
			@"trunk_link"		: @25,
			@"secondary"		: @24,
			@"tertiary"			: @23,
			// railway
			@"primary_link"		: @21,
			@"residential"		: @20,
			@"raceway"			: @19,
			@"secondary_link"	: @10,
			@"tertiary_link"	: @17,
			@"living_street"	: @16,
			@"road"				: @15,
			@"unclassified"		: @14,
			@"service"			: @13,
			@"bus_guideway"		: @12,
			@"track"			: @11,
			@"pedestrian"		: @10,
			@"cycleway"			: @9,
			@"path"				: @8,
			@"bridleway"		: @7,
			@"footway"			: @6,
			@"steps"			: @5,
			@"construction"		: @4,
			@"proposed"			: @3,
		};
	});

	NSInteger priority;
	if ( object.modifyCount ) {
		priority = 33;
	} else {
		if ( _renderPriority == 0 ) {
			if ( [_key isEqualToString:@"natural"] && [_value isEqualToString:@"coastline"] ) {
				_renderPriority = 32;
			} else if ( [_key isEqualToString:@"natural"] && [_value isEqualToString:@"water"] ) {
				_renderPriority = 31;
			} else if ( [_key isEqualToString:@"waterway"] && [_value isEqualToString:@"riverbank"] ) {
				_renderPriority = 30;
			} else if ( [_key isEqualToString:@"landuse"] ) {
				_renderPriority = 29;
			} else if ( [_key isEqualToString:@"highway"] && _value  && (_renderPriority = [highwayDict[_value] integerValue]) > 0 ) {
				(void)0;
			} else if ( [_key isEqualToString:@"railway"] ) {
				_renderPriority = 22;
			} else if ( self == g_AddressRender ) {
				_renderPriority = 1;
			} else {
				_renderPriority = 2;
			}
		}
		priority = _renderPriority;
	}

	NSInteger bonus;
	if ( object.isWay || object.isRelation.isMultipolygon ) {
		bonus = 2;
	} else if ( object.isRelation ) {
		bonus = 1;
	} else {
		bonus = 0;
	}
	priority = 3*priority + bonus;
	assert( priority < RenderInfoMaxPriority );
	return priority;
}

@end




@implementation RenderInfoDatabase

+(RenderInfoDatabase *)sharedRenderInfoDatabase
{
	static RenderInfoDatabase * _database = nil;
	if ( _database == nil ) {
		_database = [self new];
	}
	return _database;
}

+(NSMutableArray *)readConfiguration
{
	NSData * text = [NSData dataWithContentsOfFile:@"RenderInfo.json"];
	if ( text == nil ) {
		NSString * path = [[NSBundle mainBundle] pathForResource:@"RenderInfo" ofType:@"json"];
		text = [NSData dataWithContentsOfFile:path];
	}
	NSDictionary * features = [NSJSONSerialization JSONObjectWithData:text options:0 error:NULL];

	NSMutableArray * renderList = [NSMutableArray new];

	[features enumerateKeysAndObjectsUsingBlock:^(NSString * feature, NSDictionary * dict, BOOL * _Nonnull stop) {
		NSArray * keyValue = [feature componentsSeparatedByString:@"/"];
		RenderInfo * render = [RenderInfo new];
		render.key				= keyValue[0];
		render.value			= keyValue.count > 1 ? keyValue[1] : @"";
		render.lineColor		= [RenderInfo colorForHexString:dict[@"lineColor"]];
		render.areaColor		= [RenderInfo colorForHexString:dict[@"areaColor"]];
		render.lineWidth		= ((NSNumber *)dict[@"lineWidth"]).doubleValue;
		[renderList addObject:render];
	}];
	return renderList;
}


-(id)init
{
	self = [super init];
	if ( self ) {
		_allFeatures = [RenderInfoDatabase readConfiguration];
		_keyDict = [NSMutableDictionary new];
		for ( RenderInfo * tag in _allFeatures ) {
			NSMutableDictionary * valDict = [_keyDict objectForKey:tag.key];
			if ( valDict == nil ) {
				valDict = [NSMutableDictionary dictionaryWithObject:tag forKey:tag.value];
				[_keyDict setObject:valDict forKey:tag.key];
			} else {
				[valDict setObject:tag forKey:tag.value];
			}
		}
	}
	return self;
}

-(RenderInfo *)renderInfoForObject:(OsmBaseObject *)object
{
	NSDictionary * tags = object.tags;
	// if the object is part of a rendered relation than inherit that relation's tags
	if ( object.parentRelations.count && object.isWay && !object.hasInterestingTags ) {
		for ( OsmRelation * parent in object.parentRelations ) {
			if ( parent.isBoundary ) {
				tags = parent.tags;
				break;
			}
		}
	}

	// try exact match
	__block RenderInfo * best = nil;
	__block BOOL isDefault = NO;
	[tags enumerateKeysAndObjectsUsingBlock:^(NSString * key,NSString * value,BOOL * stop){
		NSDictionary * valDict = [_keyDict objectForKey:key];
		RenderInfo * render = valDict[value];
		if ( render == nil ) {
			render = valDict[@""];
			if ( render )
				isDefault = YES;
		}

		if ( render == nil )
			return;
		if ( best == nil || isDefault || (best.lineColor == nil && render.lineColor) )
			best = render;
		if ( render.lineColor == nil )
			return;
		// DLog(@"render %@=%@",key,value);
		*stop = YES;
	}];
	if ( best ) {
		return best;
	}

	// check if it is an address point
	BOOL isAddress = object.isNode && object.tags.count > 0;
	if ( isAddress ) {
		for ( NSString * key in object.tags ) {
			if ( ![key hasPrefix:@"addr:"] ) {
				isAddress = NO;
				break;
			}
		}
		if ( isAddress ) {
			if ( g_AddressRender == nil ) {
				g_AddressRender = [RenderInfo new];
				g_AddressRender.key = @"ADDRESS";
				g_AddressRender.lineWidth = 0.0;
			}
			return g_AddressRender;
		}
	}

	if ( g_DefaultRender == nil ) {
		g_DefaultRender = [RenderInfo new];
		g_DefaultRender.key = @"DEFAULT";
#if TARGET_OS_IPHONE
		g_DefaultRender.lineColor = [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
#else
		g_DefaultRender.lineColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
#endif
		g_DefaultRender.lineWidth = 0.0;
	}
	return g_DefaultRender;
}

@end

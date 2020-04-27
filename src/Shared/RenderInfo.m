//
//  TagInfo.m
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


-(RenderInfo *)copy
{
	RenderInfo * copy = [RenderInfo new];
	copy.key			= self.key;
	copy.value			= self.value;
	copy.geometry		= self.geometry;
	copy.lineColor		= self.lineColor;
	copy.lineWidth		= self.lineWidth;
	copy.areaColor		= self.areaColor;
	return copy;
}

-(NSString *)description
{
	return [NSString stringWithFormat:@"%@ %@=%@ %@", [super description], _key, _value, _geometry];
}

-(BOOL)isAddressPoint
{
	return self == g_AddressRender;
}


+(NSColor *)colorForString:(NSString *)text
{
	if ( text == nil )
		return nil;
	int r = 0, g = 0, b = 0;
	sscanf( text.UTF8String, "%2x%2x%2x", &r, &g, &b);
#if TARGET_OS_IPHONE
	return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
#else
	return [NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
#endif
}


-(NSInteger)renderPriority:(OsmBaseObject *)object
{
	static NSDictionary * highwayDict = nil;
	if ( highwayDict == nil ) {
		highwayDict = @{
			@"motorway"			: @4000,
			@"trunk"			: @3000,
			@"motorway_link"	: @2100,
			@"primary"			: @2000,
			@"trunk_link"		: @1000,
			@"primary_link"		: @1200,
			@"secondary"		: @1500,
			@"tertiary"			: @1400,
			@"residential"		: @1200,
			@"raceway"			: @1110,
			@"secondary_link"	: @1100,
			@"tertiary_link"	: @1050,
			@"living_street"	: @1020,
			@"road"				: @1000,
			@"unclassified"		: @900,
			@"service"			: @710,
			@"bus_guideway"		: @700,
			@"track"			: @500,
			@"pedestrian"		: @200,
			@"cycleway"			: @130,
			@"path"				: @120,
			@"bridleway"		: @110,
			@"footway"			: @100,
			@"steps"			: @90,
			@"construction"		: @80,
			@"proposed"			: @70,
		};
	}

	if ( _renderPriority ) {
		if ( object.isWay || object.isRelation.isMultipolygon )
			return _renderPriority + 2;
		if ( object.isRelation )
			return _renderPriority + 1;
		return _renderPriority;
	}

	if ( [_key isEqualToString:@"natural"] && [_value isEqualToString:@"coastline"] ) {
		return _renderPriority = 10000;
	}
	if ( [_key isEqualToString:@"natural"] && [_value isEqualToString:@"water"] ) {
		return _renderPriority = 9000;
	}
	if ( [_key isEqualToString:@"waterway"] && [_value isEqualToString:@"riverbank"] ) {
		return _renderPriority = 5000;
	}
	if ( [_key isEqualToString:@"highway"] ) {
		if ( _value ) {
			id priority = highwayDict[_value];
			_renderPriority = [priority integerValue];
			if ( _renderPriority )
				return _renderPriority;
		}
	}
	if ( [_key isEqualToString:@"railway"] ) {
		return _renderPriority = 1250;
	}

	// address points are extra low priority
	if ( self == g_AddressRender ) {
		return _renderPriority = 40;
	}

	// get a default value
	_renderPriority = 50;
	return [self renderPriority:object];
}

@end




@implementation RenderInfoDatabase

+(RenderInfoDatabase *)sharedTagInfoDatabase
{
	static RenderInfoDatabase * _database = nil;
	if ( _database == nil ) {
		_database = [self new];
	}
	return _database;
}

+(NSMutableArray *)readXml
{
	NSError * error = nil;
	NSMutableArray * tagList = [NSMutableArray new];
	NSMutableArray * defaults = [NSMutableArray new];
	NSString * text = [NSString stringWithContentsOfFile:@"TagInfo.xml" encoding:NSUTF8StringEncoding error:&error];
	if ( text == nil ) {
		NSString * path = [[NSBundle mainBundle] pathForResource:@"TagInfo" ofType:@"xml"];
		text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
	}
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
	NSXMLElement * root = [doc rootElement];
	for ( NSXMLElement * tag in root.children ) {

		RenderInfo * tagType = [RenderInfo new];
		tagType.key				= [tag attributeForName:@"key"].stringValue;
		tagType.value			= [tag attributeForName:@"value"].stringValue;
		tagType.geometry		= [tag attributeForName:@"type"].stringValue;
		tagType.lineColor		= [RenderInfo colorForString:[tag attributeForName:@"lineColor"].stringValue];
		tagType.areaColor		= [RenderInfo colorForString:[tag attributeForName:@"areaColor"].stringValue];
		tagType.lineWidth		= [tag attributeForName:@"lineWidth"].stringValue.doubleValue;

		if ( [tag.name isEqualToString:@"tag"] ) {
			[tagList addObject:tagType];
		} else if ( [tag.name isEqualToString:@"default"] ) {
			assert( tagType.value == nil );	// not implemented
			[defaults addObject:tagType];
		} else {
			assert(NO);
		}
	}
	for ( RenderInfo * def in defaults ) {
		for ( RenderInfo * tag in tagList ) {
			if ( [tag.key isEqualToString:def.key] ) {
				if ( tag.areaColor == nil )
					tag.areaColor = def.areaColor;
				if ( tag.lineColor == nil )
					tag.lineColor = def.lineColor;
				if ( tag.lineWidth == 0.0 )
					tag.lineWidth = def.lineWidth;
			}
		}
	}
	return tagList;
}

-(id)initWithXmlFile:(NSString *)file
{
	self = [super init];
	if ( self ) {
		_allTags = [RenderInfoDatabase readXml];
		_keyDict = [NSMutableDictionary new];
		for ( RenderInfo * tag in _allTags ) {
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

-(RenderInfo *)tagInfoForKey:(NSString *)key value:(NSString *)value
{
	NSDictionary * valDict = [_keyDict objectForKey:key];
	return [valDict objectForKey:value];
}

-(RenderInfo *)tagInfoForObject:(OsmBaseObject *)object
{
	// try exact match
	__block RenderInfo * best = nil;
	[object.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key,NSString * value,BOOL * stop){
		NSDictionary * valDict = [_keyDict objectForKey:key];
		if ( valDict ) {
			RenderInfo * render = [valDict objectForKey:value];
			if ( render == nil )
				return;
			if ( best == nil || (best.lineColor == nil && render.lineColor) )
				best = render;
			if ( render.lineColor == nil )
				return;
			// DLog(@"render %@=%@",key,value);
			*stop = YES;
		}
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

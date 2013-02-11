//
//  TagInfo.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "DLog.h"
#import "OsmObjects.h"
#import "TagInfo.h"

#if TARGET_OS_IPHONE
#include "DDXML.h"
#endif


@implementation KeyValue
-(id)init
{
	self = [super init];
	if ( self ) {
		self.key = @"(new tag)";
		self.value = @"(new value)";
	}
	return self;
}
-(id)initWithKey:(NSString *)key value:(id)value
{
	self = [super init];
	if ( self ) {
		self.key = key;
		self.value = value;
	}
	return self;
}
+(id)keyValueWithKey:(NSString *)key value:(id)value
{
	return [[KeyValue alloc] initWithKey:key value:value];
}

+(NSString *)validateString:(NSString *)value
{
	NSString * value2 = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ( ! [value isEqualToString:value2] ) {
		// only change value if necessary, to keep KVO happy
		value = value2;
	}
	if ( value.length == 0 )
		return value;
	if ( [value characterAtIndex:0] == '(' && [value characterAtIndex:value.length-1] == ')' )
		return nil;
	if ( [value rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]].length == 0 )
		return nil;
	return value;
}

-(BOOL)validateKey:(id *)ioValue error:(NSError * __autoreleasing *)outError
{
	NSString * ok = [self.class validateString:*ioValue];
	if ( !ok ) {
		if ( outError ) {
			NSDictionary * userInfoDict = @{ NSLocalizedDescriptionKey : @"Invalid tag key" };
			*outError = [[NSError alloc] initWithDomain:@"tag" code:1 userInfo:userInfoDict];
		}
		return NO;
	}
	*ioValue = ok;
    return YES;
}
-(BOOL)validateValue:(id *)ioValue error:(NSError * __autoreleasing *)outError
{
	NSString * ok = [self.class validateString:*ioValue];
	if ( !ok ) {
		if ( outError ) {
			NSDictionary * userInfoDict = @{ NSLocalizedDescriptionKey : @"Invalid tag value" };
			*outError = [[NSError alloc] initWithDomain:@"tag" code:2 userInfo:userInfoDict];
		}
		return NO;
	}
	*ioValue = ok;
    return YES;
}
@end


@implementation TagInfo

@synthesize iconName = _iconName;

static TagInfo * g_DefaultRender = nil;

-(NSImage *)icon
{
	if ( _icon == nil ) {
		NSString * name = self.iconName;
		if ( name.length ) {
			if ( ![name hasSuffix:@".png"] )
				name = [name stringByAppendingString:@".p.64.png"];
			_icon = [NSImage imageNamed:name];
			if ( _icon == nil ) {
				DLog(@"missing icon for path '%@'", name);
			}
		}
	}
	return _icon;
}
-(CGImageRef)cgIcon
{
	if ( _cgIcon == NULL ) {
#if TARGET_OS_IPHONE
		NSImage * image = [self icon];
		_cgIcon = image.CGImage;
#else
		NSString * name = self.iconName;
		if ( name.length ) {
			name = [name stringByAppendingString:@".p.64.png"];
			name = [[NSBundle mainBundle] pathForImageResource:name];
			CGDataProviderRef provider = CGDataProviderCreateWithFilename(name.UTF8String);
			if ( provider )  {
				_cgIcon = CGImageCreateWithPNGDataProvider( provider, nil, true, kCGRenderingIntentDefault );
				CGDataProviderRelease( provider );
			}
		}
#endif
	}
	return _cgIcon;
}

-(NSString *)friendlyName2
{
	NSString * text = [NSString stringWithFormat:@"%@ (%@)", _value, _key];
	text = [text stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	text = text.capitalizedString;
	return text;
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
+(NSString *)stringForColor:(NSColor *)color
{
	if ( color == nil )
		return nil;
	CGFloat r,g,b,a;
	[color getRed:&r green:&g blue:&b alpha:&a];
	return [NSString stringWithFormat:@"%02lX%02lX%02lX",lround(r*255),lround(g*255),lround(b*255)];
}

-(NSString *)lineColorText
{
	if ( self.lineColor == nil )
		return nil;
	return [TagInfo stringForColor:self.lineColor];
}
-(void)setLineColorText:(NSString *)lineColorText
{
	self.lineColor = [TagInfo colorForString:lineColorText];
}
-(NSString *)areaColorText
{
	if ( self.areaColor == nil )
		return nil;
	return [TagInfo stringForColor:self.areaColor];
}
-(void)setAreaColorText:(NSString *)areaColorText
{
	self.areaColor = [TagInfo colorForString:areaColorText];
}

-(NSString *)iconName
{
	return _iconName;
}
-(void)setIconName:(NSString *)iconName
{
	_iconName = iconName;
	_icon = nil;
	_cgIcon = NULL;
}


-(CGFloat)renderSize:(OsmBaseObject *)object
{
	static NSDictionary * highwayDict = nil;
	if ( highwayDict == nil ) {
		highwayDict = @{
		@"motorway"			: @4,
		@"motorway_link"	: @2,
		@"trunk"			: @3,
		@"trunk_link"		: @1,
		@"primary"			: @2,
		@"primary_link"		: @1,
		@"secondary"		: @1.5,
		@"secondary_link"	: @1,
		@"tertiary"			: @1.4,
		@"tertiary_link"	: @1,
		@"living_street"	: @1,
		@"pedestrian"		: @0.2,
		@"residential"		: @1.2,
		@"unclassified"		: @0.9,
		@"service"			: @0.7,
		@"track"			: @0.5,
		@"bus_guideway"		: @0.7,
		@"raceway"			: @1.1,
		@"road"				: @1,
		@"path"				: @0.1,
		@"footway"			: @0.1,
		@"cycleway"			: @0.11,
		@"bridleway"		: @0.11,
		@"steps"			: @0.09,
		@"proposed"			: @0.1,
		@"construction"		: @0.1,
		};
	}
	if ( _renderSize == 0.0 ) {

		if ( [_key isEqualToString:@"natural"] && [_value isEqualToString:@"coastline"] ) {
			return _renderSize = 10;
		}
		if ( [_key isEqualToString:@"waterway"] && [_value isEqualToString:@"riverbank"] ) {
			return _renderSize = 5;
		}
		if ( [_key isEqualToString:@"highway"] ) {
			if ( _value ) {
				id priority = highwayDict[_value];
				_renderSize = [priority doubleValue];
				if ( _renderSize )
					return _renderSize;
			}
		}
		_renderSize = nan("");
	}
	if ( isnan(_renderSize) )
		return object.isWay ? 1.0 : 0.05;

	return _renderSize;
}

@end


@implementation TagInfoDatabase

+(TagInfoDatabase *)sharedTagInfoDatabase
{
	static TagInfoDatabase * _database = nil;
	if ( _database == nil ) {
		_database = [self new];
	}
	return _database;
}

+(NSMutableArray *)readXml
{
	NSError * error = nil;
	NSMutableArray * array = [NSMutableArray new];
	NSString * text = [NSString stringWithContentsOfFile:@"TagInfo.xml" encoding:NSUTF8StringEncoding error:&error];
	if ( text == nil ) {
		NSString * path = [[NSBundle mainBundle] pathForResource:@"TagInfo" ofType:@"xml"];
		text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
	}
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
	NSXMLElement * root = [doc rootElement];
	for ( NSXMLElement * tag in root.children ) {
		TagInfo * tagType = [TagInfo new];
		tagType.key				= [tag attributeForName:@"key"].stringValue;
		tagType.value			= [tag attributeForName:@"value"].stringValue;
		tagType.friendlyName	= [tag attributeForName:@"name"].stringValue;
		tagType.description		= [tag attributeForName:@"description"].stringValue;
		tagType.type			= [tag attributeForName:@"type"].stringValue;
		tagType.belongsTo		= [tag attributeForName:@"belongsTo"].stringValue;
		tagType.iconName		= [tag attributeForName:@"iconName"].stringValue;
		tagType.wikiPage		= [tag attributeForName:@"wikiPage"].stringValue;
		tagType.lineColor		= [TagInfo colorForString:[tag attributeForName:@"lineColor"].stringValue];
		tagType.areaColor		= [TagInfo colorForString:[tag attributeForName:@"areaColor"].stringValue];
		tagType.lineWidth		= [tag attributeForName:@"lineWidth"].stringValue.doubleValue;
		[array addObject:tagType];
	}
	return array;
}

-(id)initWithXmlFile:(NSString *)file
{
	self = [super init];
	if ( self ) {
		_allTags = [TagInfoDatabase readXml];
		_keyDict = [NSMutableDictionary new];
		for ( TagInfo * tag in _allTags ) {
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

-(id)init
{
	NSString * path = [[NSBundle mainBundle] pathForResource:@"TagInfo.menu" ofType:@"xml"];
	self = [self initWithXmlFile:path];
	return self;
}

#if TARGET_OS_IPHONE
// belongTo means that the text appears either as the key or the belongTo field
-(NSArray *)subitemsOfType:(NSString *)type belongTo:(NSString *)belongTo
{
	// get set of key values for children (creates an array of strings)
	NSArray * childTags = [self tagsBelongTo:belongTo type:type];
	NSMutableSet * set = [NSMutableSet new];
	for ( TagInfo * child in childTags ) {
		[set addObject:child.key];
	}
	NSArray * tags = [set allObjects];
	tags = [tags filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString * key, NSDictionary *bindings) {
		return [[OsmBaseObject typeKeys] containsObject:key];
	}]];

	// get values for key (creates an array of TagInfo)
	NSDictionary * valueDict = [_keyDict valueForKey:belongTo];
	NSArray * valueArray = [valueDict allValues];
	valueArray = [valueArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TagInfo * tagInfo, NSDictionary *bindings) {
		return [tagInfo.type rangeOfString:type].length > 0;
	}]];

	tags = [tags arrayByAddingObjectsFromArray:valueArray];

	tags = [tags sortedArrayUsingComparator:^NSComparisonResult(NSString * obj1, NSString * obj2) {
		NSString * s1 = [obj1 isKindOfClass:[NSString class]] ? obj1 : ((TagInfo *)obj1).friendlyName;
		NSString * s2 = [obj2 isKindOfClass:[NSString class]] ? obj2 : ((TagInfo *)obj2).friendlyName;
		return [s1 caseInsensitiveCompare:s2];
	}];
	return tags;
}

- (NSArray *)itemsForTag:(NSString *)type matching:(NSString *)searchText
{
	return [_allTags filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TagInfo * tag, NSDictionary *bindings) {
		if ( [tag.value rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound )
			return YES;
		if ( [tag.key rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound )
			return YES;
		if ( tag.description && [tag.description rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound )
			return YES;
		return NO;
	}]];
}


#else
-(NSMenu *)menuWithTag:(NSString *)key target:(id)target action:(SEL)action
{
	NSMenu * menu = [[NSMenu alloc] initWithTitle:key];

	// if other tags belong to this tag then add them as submenus
	NSArray * childTags = [self tagsBelongTo:key];
	if ( childTags.count ) {

		// get set of key values for children
		NSMutableSet * set = [NSMutableSet new];
		for ( TagInfo * child in childTags ) {
			[set addObject:child.key];
		}

		NSArray * keyArray = [set allObjects];
		keyArray = [keyArray sortedArrayUsingComparator:^NSComparisonResult(NSString * obj1, NSString * obj2) {
			return [obj1 caseInsensitiveCompare:obj2];
		}];
		for ( NSString * key in keyArray ) {

			NSMenu * subMenu = [self menuWithTag:key target:target action:action];
			assert( subMenu.numberOfItems > 0 );
			if ( subMenu.numberOfItems > 0 ) {
				NSString * name = [key capitalizedString];
				NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:name action:NULL keyEquivalent:@""];
				[item setSubmenu:subMenu];
				[menu addItem:item];
			}
		}

	} else {

		// get values for key
		NSDictionary * valueDict = [_keyDict valueForKey:key];
		NSArray * valueArray = [valueDict allValues];
		valueArray = [valueArray sortedArrayUsingComparator:^NSComparisonResult(TagInfo * obj1, TagInfo * obj2) {
			return [obj1.friendlyName caseInsensitiveCompare:obj2.friendlyName];
		}];
		for ( TagInfo * tagInfo in valueArray ) {
			NSString * name = tagInfo.friendlyName ? tagInfo.friendlyName : [NSString stringWithFormat:@"%@=%@",tagInfo.key,tagInfo.value];
			NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:name action:action keyEquivalent:@""];
			item.target = target;
			item.representedObject = tagInfo;
			[menu addItem:item];
		};
	}
	return menu;
}

-(NSMenu *)tagNodeMenuWithTarget:(id)target action:(SEL)action
{
	return [self menuWithTag:@"node" target:(id)target action:(SEL)action];
}
-(NSMenu *)tagWayMenuWithTarget:(id)target action:(SEL)action
{
	return nil;
}
#endif


-(NSArray *)tagsBelongTo:(NSString *)parentItem type:(NSString *)type
{
	__block NSMutableArray * list = [NSMutableArray new];
	[_keyDict enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSDictionary * valDict, BOOL *stop) {
		[valDict enumerateKeysAndObjectsUsingBlock:^(NSString * value, TagInfo * tagInfo, BOOL *stop) {
			if ( [tagInfo.type rangeOfString:type].length > 0 ) {
				if ( parentItem ? [tagInfo.belongsTo rangeOfString:parentItem].length > 0 : tagInfo.belongsTo.length == 0 ) {
					[list addObject:tagInfo];
					*stop = YES;
				}
			}
		}];
	}];
	return list;
}

-(NSArray *)tagsForNodes
{
	return [self tagsBelongTo:nil type:@"node"];
}

-(NSSet *)allTagKeys
{
	static NSMutableSet * set = nil;
	if ( set == nil ) {
		set = [NSMutableSet set];
		for ( TagInfo * tag in _allTags ) {
			[set addObject:tag.key];
		}
		[set addObjectsFromArray:@[
			@"access",
			@"admin_level",
			@"addr:housenumber",
			@"addr:street",
			@"addr:city",
			@"addr:country",
			@"addr:postcode",
			@"addr:state",
			@"addr:housename",
			@"addr:interpolation",
			@"alt_name",
			@"area",
			@"bicycle",
			@"bridge",
			@"crossing",
			@"cuisine",
			@"designation",
			@"ele",
			@"fixme",
			@"foot",
			@"height",
			@"lanes",
			@"layer",
			@"maxspeed",
			@"name",
			@"note",
			@"operator",
			@"ref",
			@"source",
			@"website",
			@"width",
		 ]];
	}
	return set;
}

-(NSSet *)allTagValuesForKey:(NSString *)key
{
	NSMutableSet * set = [NSMutableSet set];
	for ( TagInfo * tag in _allTags ) {
		if ( [tag.key isEqualToString:key] ) {
			[set addObject:tag.value];
		}
	}
	if ( [key isEqualToString:@"wifi"] ) {
		[set addObjectsFromArray:[self wifiValues]];
	} else if ( [key isEqualToString:@"cuisine"] ) {
		[set addObjectsFromArray:[self cuisineEthnicValues]];
		[set addObjectsFromArray:[self cuisineStyleValues]];
	} else if ( [key isEqualToString:@"fixme"] ) {
		[set addObjectsFromArray:[self fixmeValues]];
	} else if ( [key isEqualToString:@"source"] ) {
		[set addObjectsFromArray:[self sourceValues]];
	}


	return set;
}


-(TagInfo *)tagInfoForKey:(NSString *)key value:(NSString *)value
{
	NSDictionary * valDict = [_keyDict valueForKey:key];
	return [valDict valueForKey:value];
}

-(TagInfo *)tagInfoForObject:(OsmBaseObject *)object
{
#if 0
	if ( [[object.tags objectForKey:@"seamark:type"] isEqualToString:@"buoy_lateral"] ) {
		int i = 1;
		++i;
		--i;
	}
#endif

	// try exact match
	__block TagInfo * best = nil;
	[object.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key,NSString * value,BOOL * stop){
		NSDictionary * valDict = [_keyDict valueForKey:key];
		if ( valDict ) {
			TagInfo * render = [valDict valueForKey:value];
			if ( render == nil )
				return;
			if ( best == nil || (best.lineColor == nil && render.lineColor) || (!best.iconName && render.iconName) )
				best = render;
			if ( render.lineColor == nil && render.iconName == nil )
				return;
			// DLog(@"render %@=%@",key,value);
			*stop = YES;
		}
	}];
	if ( best )
		return best;

	if ( g_DefaultRender == nil ) {
		g_DefaultRender = [TagInfo new];
#if TARGET_OS_IPHONE
		g_DefaultRender.lineColor = [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
#else
		g_DefaultRender.lineColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
#endif
		g_DefaultRender.lineWidth = 1.0;
	}
	return g_DefaultRender;
}

-(NSArray *)cuisineStyleValues
{
	NSArray * _cuisineStyleArray = nil;
	if ( _cuisineStyleArray == nil ) {
		_cuisineStyleArray = @[
			@"bagel",
			@"barbecue",
			@"bougatsa",
			@"burger",
			@"cake",
			@"chicken",
			@"coffee_shop",
			@"crepe",
			@"couscous",
			@"curry",
			@"doughnut",
			@"fish_and_chips",
			@"fried_food",
			@"friture",
			@"ice_cream",
			@"kebab",
			@"mediterranean",
			@"noodle",
			@"pasta",
			@"pie",
			@"pizza",
			@"regional",
			@"sandwich",
			@"sausage",
			//		@"savory_pancakes",
			@"seafood",
			@"steak_house",
			@"sushi",
			];
	}
	return _cuisineStyleArray;
}

-(NSArray *)cuisineEthnicValues
{
	static NSArray * _ethnicArray = nil;
	if ( _ethnicArray == nil ) {
		_ethnicArray = @[
			@"african",
			@"american",
			@"arab",
			@"argentinian",
			@"asian",
			@"balkan",
			@"basque",
			@"brazilian",
			@"chinese",
			@"croatian",
			@"czech",
			@"french",
			@"german",
			@"greek",
			@"hawaiian",
			@"indian",
			@"iranian",
			@"italian",
			@"japanese",
			@"korean",
			@"latin_american",
			@"lebanese",
			@"mexican",
			@"peruvian",
			@"portuguese",
			@"spanish",
			@"thai",
			@"turkish",
			@"vietnamese"
		];
	}
	return _ethnicArray;
}

-(NSArray *)wifiValues
{
	return @[
			@"free",
			@"yes",
			@"no",
	  ];
}

-(NSArray *)fixmeValues
{
	return @[
			@"resurvey",
			@"name",
			@"continue",
	];
}

-(NSArray *)sourceValues
{
	return @[
			@"survey",
			@"local_knowledge",
			@"Bing",
			@"Yahoo",
	 ];
}

@end

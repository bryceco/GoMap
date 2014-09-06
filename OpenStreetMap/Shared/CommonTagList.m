//
//  CommonTagList.m
//  Go Map!!
//
//  Created by Bryce on 9/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "iosapi.h"
#import "CommonTagList.h"
#import "DLog.h"
#import "TagInfo.h"


static NSString * prettyTag( NSString * tag )
{
	tag = [tag stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	tag = [tag capitalizedString];
	return tag;
}



@implementation CommonPreset
-(instancetype)initWithName:(NSString *)name tagValue:(NSString *)value
{
	self = [super init];
	if ( self ) {
		_name = name ?: prettyTag(value);
		_tagValue = value;
	}
	return self;
}
+(instancetype)presetWithName:(NSString *)name tagValue:(NSString *)value
{
	return [[CommonPreset alloc] initWithName:name tagValue:value];
}
@end

@implementation CommonGroup
-(instancetype)initWithName:(NSString *)name tags:(NSArray *)tags
{
	self = [super init];
	if ( self ) {
#if DEBUG
		if ( tags.count )	assert( [tags.lastObject isKindOfClass:[CommonTag class]] );
#endif
		_name = name;
		_tags = tags;
	}
	return self;
}
+(instancetype)groupWithName:(NSString *)name tags:(NSArray *)tags
{
	return [[CommonGroup alloc] initWithName:name tags:tags];
}
-(void)mergeTagsFromGroup:(CommonGroup *)other
{
	if ( _tags == nil )
		_tags = other.tags;
	else
		_tags = [_tags arrayByAddingObjectsFromArray:other.tags];
}
@end


@implementation CommonTag
-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets
{
	self = [super init];
	if ( self ) {

		if ( placeholder == nil ) {
			if ( presets.count > 1 ) {
				NSMutableString * s = [NSMutableString new];
				for ( NSInteger i = 0; i < 3; ++i ) {
					if ( i >= presets.count )
						break;
					CommonPreset * p = presets[i];
					if ( p.tagValue.length >= 20 )
						continue;
					if ( s.length )
						[s appendString:@", "];
					[s appendString:p.tagValue];
				}
				[s appendString:@"..."];
				placeholder = s;
			} else {
				placeholder = @"Unknown";
			}
		}

		_name			= name;
		_tagKey			= tag;
		_placeholder	= placeholder;
		_presetList		= presets.count ? presets : nil;
	}
	return self;
}
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets
{
	return [[CommonTag alloc] initWithName:name tagKey:tag placeholder:placeholder presets:presets];
}
@end


@implementation CommonTagList

#if 0
-(NSArray *)builtinSectionNames
{
	return @[
		NSLocalizedString(@"Basic",nil),
		NSLocalizedString(@"Extras",nil),
		NSLocalizedString(@"Address",nil),
		NSLocalizedString(@"Source",nil),
		NSLocalizedString(@"Notes",nil),
	 ];
}

-(NSArray *)builtinSections
{
	return @[
		@[
			[CommonTag tagWithName:@"Type"			tag:nil					placeholder:@""							presets:@[@"",@""]],
			[CommonTag tagWithName:@"Name"			tag:@"name"				placeholder:@"McDonald's"				presets:nil],
			[CommonTag tagWithName:@"Alt Name"		tag:@"alt_name"			placeholder:@"Mickey D's"				presets:nil],
		],
		@[
			[CommonTag tagWithName:@"Cuisine"		tag:@"cuisine"			placeholder:@"burger"					presets:@[@"Cuisine", @"cuisineStyleValues", @"Ethnicity", @"cuisineEthnicValues"]],
			[CommonTag tagWithName:@"WiFi"			tag:@"wifi"				placeholder:@"free"						presets:@[@"", @"wifiValues"]],
			[CommonTag tagWithName:@"Operator"		tag:@"operator"			placeholder:@"McDonald's Corporation"	presets:nil],
			[CommonTag tagWithName:@"Ref"			tag:@"ref"				placeholder:@"reference"				presets:nil],
		],
		@[
			[CommonTag tagWithName:@"Building"		tag:@"addr:housename"	placeholder:@"Empire State Building" 	presets:nil],
			[CommonTag tagWithName:@"Number"		tag:@"addr:housenumber"	placeholder:@"350"						presets:nil],
			[CommonTag tagWithName:@"Unit"			tag:@"addr:unit"		placeholder:@"3G"						presets:nil],
			[CommonTag tagWithName:@"Street"		tag:@"addr:street"		placeholder:@"5th Avenue"				presets:nil],
			[CommonTag tagWithName:@"City"			tag:@"addr:city"		placeholder:@"New York"					presets:nil],
			[CommonTag tagWithName:@"Post Code"		tag:@"addr:postcode"	placeholder:@"10118"					presets:nil],
			[CommonTag tagWithName:@"Phone"			tag:@"phone"			placeholder:@"(212)736-3100"			presets:nil],
			[CommonTag tagWithName:@"Website"		tag:@"website"			placeholder:@"www.esbnyc.com"			presets:nil],
		],
		@[
			[CommonTag tagWithName:@"Source"		tag:@"source"			placeholder:@"local_knowledge"			presets:@[@"", @"sourceValues"]],
			[CommonTag tagWithName:@"Designation"	tag:@"designation"		placeholder:@"designation"				presets:nil],
		],
		@[
			[CommonTag tagWithName:@"Fix Me"		tag:@"fixme"			placeholder:@"needs survey"				presets:@[@"", @"fixmeValues"]],
			[CommonTag tagWithName:@"Note"			tag:@"note"				placeholder:@"done from memory"			presets:nil],
		],
	];
}
#endif

-(CommonGroup *)groupForField:(NSString *)field geometry:(NSString *)geometry
{
	static NSMutableDictionary * presetCache = nil;
	if ( presetCache == nil ) {
		presetCache = [NSMutableDictionary new];
	}

	NSString * root = [[NSBundle mainBundle] resourcePath];
	NSString * path = [NSString stringWithFormat:@"%@/presets/fields/%@.json",root,field];
	NSData * data = [NSData dataWithContentsOfFile:path];
	NSDictionary * dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if ( dict == nil )
		return nil;

	NSString * geo = dict[@"geometry"];
	if ( [geo rangeOfString:geometry].location == NSNotFound ) {
		DLog(@"skip %@",field);
		return nil;
	}

	NSString	*	type = dict[@"type"];
	NSArray		*	keyArray = dict[ @"keys" ];
	NSString	*	givenName = dict[@"label"];
	NSString	*	placeholder = dict[@"placeholder"];
	NSDictionary *	optionStringsDict = dict[ @"strings" ][ @"options" ];
	NSArray		*	optionArray = dict[ @"options" ];
	DLog(@"%@",dict);


	if ( [type isEqualToString:@"defaultcheck"] || [type isEqualToString:@"check"] ) {

		NSArray * presets = @[ [CommonPreset presetWithName:@"Yes" tagValue:@"yes"], [CommonPreset presetWithName:@"No" tagValue:@"no"] ];
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:presets];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"radio"] ) {

		NSMutableArray * presets = [NSMutableArray new];
		if ( keyArray ) {
			for ( NSString * k in keyArray ) {
				NSString * label = optionStringsDict[ k ];
				[presets addObject:[CommonPreset presetWithName:label tagValue:k]];
			}
		} else if ( optionArray ) {
			for ( NSString * v in optionArray ) {
				[presets addObject:[CommonPreset presetWithName:nil tagValue:v]];
			}
		} else {
#if DEBUG
			assert(NO);
#endif
		}

		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:presets];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"combo"] ) {

		NSMutableArray * presets = [NSMutableArray new];
		if ( optionStringsDict ) {

			[optionStringsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
				[presets addObject:[CommonPreset presetWithName:v tagValue:k]];
			}];
			[presets sortUsingComparator:^NSComparisonResult(CommonPreset * obj1, CommonPreset * obj2) {
				return [obj1.name compare:obj2.name];
			}];

		} else if ( optionArray ) {

			for ( NSString * v in optionArray ) {
				[presets addObject:[CommonPreset presetWithName:nil tagValue:v]];
			}

		} else {

			// check tagInfo
			if ( presetCache[field] ) {
				// already got them once
				presets = presetCache[field];
			} else {
				NSString * urlText = [NSString stringWithFormat:@"http://taginfo.openstreetmap.org/api/4/key/values?key=%@&page=1&rp=25&sortname=count_all&sortorder=desc",field];
				NSURL * url = [NSURL URLWithString:urlText];
				data = [NSData dataWithContentsOfURL:url];
				optionStringsDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
				NSArray * values = optionStringsDict[@"data"];
				for ( NSDictionary * v in values ) {
					if ( [v[@"fraction"] doubleValue] < 0.01 )
						continue;
					NSString * val = v[@"value"];
					[presets addObject:[CommonPreset presetWithName:nil tagValue:val]];
				}
				[presetCache setObject:presets forKey:field];
			}
		}

		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:presets];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"address"] ) {

		NSString * ref = dict[@"reference"][@"key"];
		NSDictionary * placeholders = dict[ @"strings" ][ @"placeholders" ];
		NSMutableArray * addrs = [NSMutableArray new];
		for ( NSString * k in dict[@"keys"] ) {
			NSString * name = [k substringFromIndex:ref.length+1];
			placeholder = placeholders[name];
			name = prettyTag( name );
			CommonTag * tag = [CommonTag tagWithName:name tagKey:k placeholder:placeholder presets:nil];
			[addrs addObject:tag];
		}
		CommonGroup * group = [CommonGroup groupWithName:givenName tags:addrs];
		return group;

	} else if ( [type isEqualToString:@"text"] ||
			    [type isEqualToString:@"number"] ||
			    [type isEqualToString:@"textarea"] ||
			    [type isEqualToString:@"tel"] ||
			    [type isEqualToString:@"url"] ||
			    [type isEqualToString:@"wikipedia"] )
	{

		// no presets
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"maxspeed"] ) {

		// special case
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"access"] ) {

		// special case
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	} else {

#if DEBUG
		assert(NO);
#endif
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:field placeholder:placeholder presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	}
}

-(void)setPresetsForKey:(NSString *)key value:(NSString *)value geometry:(NSString *)geometry
{
	CommonTag * typeTag = [CommonTag tagWithName:@"Type" tagKey:nil placeholder:@"" presets:@[@"",@""]];
	CommonTag * nameTag = [CommonTag tagWithName:@"Name" tagKey:@"name" placeholder:@"common name" presets:nil];
	CommonGroup * typeGroup = [CommonGroup groupWithName:@"Type" tags:@[ typeTag, nameTag ] ];

	_sectionList = [NSMutableArray arrayWithArray:@[ typeGroup ]];

	NSString * root = [[NSBundle mainBundle] resourcePath];
	NSString * path = [NSString stringWithFormat:@"%@/presets/presets/%@/%@.json",root,key,value];
	NSData * data = [NSData dataWithContentsOfFile:path];
	if ( data ) {
		NSDictionary * dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		NSArray * fields = dict[ @"fields" ];

		for ( NSString * field in fields ) {
			CommonGroup * group = [self groupForField:field geometry:geometry];
			if ( group == nil )
				continue;
			// if both this group and the previous don't have a name then merge them
			if ( group.name == nil && _sectionList.count > 1 ) {
				CommonGroup * prev = _sectionList.lastObject;
				if ( prev.name == nil ) {
					[prev mergeTagsFromGroup:group];
					continue;
				}
			}
			[_sectionList addObject:group];
		}
	}

	NSArray * extras = @[ @"elevation", @"note", @"phone", @"website", @"wheelchair", @"wikipedia" ];
	CommonGroup * extraGroup = [CommonGroup groupWithName:@"Other" tags:nil];
	for ( NSString * field in extras ) {
		CommonGroup * group = [self groupForField:field geometry:geometry];
		[extraGroup mergeTagsFromGroup:group];
	}
	[_sectionList addObject:extraGroup];
}

-(instancetype)init
{
	self = [super init];
	if ( self ) {
#if 0
		_sectionList = [[NSUserDefaults standardUserDefaults] objectForKey:@"CommonTagList"];
		if ( _sectionList.count == 0 ) {
			_sectionList		= [[self builtinSections] mutableCopy];
			_sectionNameList	= [[self builtinSectionNames] mutableCopy];
		}

		for ( NSInteger i = 0; i < _sectionList.count; i++ ) {
			NSArray * tagList = _sectionList[ i ];

			if ( [tagList isKindOfClass:[NSString class]] ) {
				// expand using taginfo
				SEL selector = NSSelectorFromString((id)tagList);;
				TagInfoDatabase * database = [TagInfoDatabase sharedTagInfoDatabase];
				if ( selector && [database respondsToSelector:selector]	) {
					IMP imp = [database methodForSelector:selector];
					NSArray * (*func)(id, SEL) = (void *)imp;
					tagList = func(database, selector);
				} else {
					tagList = @[];
				}
				_sectionList[i] = [tagList mutableCopy];
			} else {
				// should already be an array
				assert( [tagList isKindOfClass:[NSArray class]] );
				_sectionList[i] = [tagList mutableCopy];
			}
		}
#endif
	}
	return self;
}

-(NSInteger)sectionCount
{
	return _sectionList.count;
}

-(CommonGroup *)groupAtIndex:(NSInteger)index
{
	return _sectionList[ index ];
}

-(NSInteger)tagsInSection:(NSInteger)index
{
	CommonGroup * group = _sectionList[ index ];
	return group.tags.count;
}

-(CommonTag *)tagAtSection:(NSInteger)section row:(NSInteger)row
{
	CommonGroup * group = _sectionList[ section ];
	CommonTag * tag = group.tags[ row ];
	return tag;
}

-(CommonTag *)tagAtIndexPath:(NSIndexPath *)indexPath
{
	return [self tagAtSection:indexPath.section row:indexPath.row];
}

#if 0
-(void)insertTag:(CommonTag *)tag atIndexPath:(NSIndexPath *)indexPath
{
	CommonGroup * group = _sectionList[ indexPath.section ];
	[group.tags insertObject:tag atIndex:indexPath.row];
}

-(void)removeTagAtIndexPath:(NSIndexPath *)indexPath
{
	NSMutableArray * tags = _sectionList[ indexPath.section ];
	[tags removeObjectAtIndex:indexPath.row];
}
#endif

@end

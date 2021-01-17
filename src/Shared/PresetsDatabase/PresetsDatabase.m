//
//  CommonTagList.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/4/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "MapView.h"

#import "iosapi.h"
#import "DLog.h"
#import "PresetsDatabase.h"
#import "RenderInfo.h"

#if !TARGET_OS_IPHONE
const int UIKeyboardTypeDefault					= 0;
const int UIKeyboardTypeNumbersAndPunctuation 	= 1;
const int UIKeyboardTypeURL						= 2;

const int UITextAutocapitalizationTypeNone		= 0;
const int UITextAutocapitalizationTypeSentences = 1;
const int UITextAutocapitalizationTypeWords		= 2;
#endif

static NSMutableDictionary<NSString *,NSMutableArray *> 	* g_taginfoCache;			// OSM TagInfo database in the cloud: contains either a group or an array of values


static NSString * PrettyTag( NSString * tag )
{
	static NSRegularExpression * expr = nil;
	if ( expr == nil )
		expr = [NSRegularExpression regularExpressionWithPattern:@"^[abcdefghijklmnopqrstuvwxyz_:]+$"
														 options:0
														   error:NULL];
	if ( [expr matchesInString:tag options:0 range:NSMakeRange(0,tag.length)] ) {
		tag = [tag stringByReplacingOccurrencesOfString:@"_" withString:@" "];
		tag = [tag capitalizedString];
	}
	return tag;
}


BOOL IsOsmBooleanTrue( NSString * value )
{
    if ( [value isEqualToString:@"true"] )
        return YES;
    if ( [value isEqualToString:@"yes"] )
        return YES;
    if ( [value isEqualToString:@"1"] )
        return YES;
    return NO;
}

@implementation PresetValue
-(instancetype)initWithName:(NSString *)name details:(NSString *)details tagValue:(NSString *)value
{
	self = [super init];
	if ( self ) {
		_name = name ?: PrettyTag(value);
		_details = details;
		_tagValue = value;
	}
	return self;
}
+(instancetype)presetValueWithName:(NSString *)name details:(NSString *)details tagValue:(NSString *)value
{
	return [[PresetValue alloc] initWithName:name details:details tagValue:value];
}
-(void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_name forKey:@"name"];
	[coder encodeObject:_details forKey:@"details"];
	[coder encodeObject:_tagValue forKey:@"tagValue"];
}

-(instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_name = [coder decodeObjectForKey:@"name"];
		_details = [coder decodeObjectForKey:@"details"];
		_tagValue = [coder decodeObjectForKey:@"tagValue"];
	}
	return self;
}
-(NSString *)description
{
	return self.name;
}
@end



@implementation PresetKey
-(void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_name forKey:@"name"];
	[coder encodeObject:_tagKey forKey:@"tagKey"];
	[coder encodeObject:_placeholder forKey:@"placeholder"];
	[coder encodeObject:_presetList forKey:@"presetList"];
	[coder encodeInteger:_keyboardType forKey:@"keyboardType"];
	[coder encodeInteger:_autocapitalizationType forKey:@"capitalize"];
}

-(instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_name = [coder decodeObjectForKey:@"name"];
		_tagKey = [coder decodeObjectForKey:@"tagKey"];
		_placeholder = [coder decodeObjectForKey:@"placeholder"];
		_presetList = [coder decodeObjectForKey:@"presetList"];
		_keyboardType = [coder decodeIntegerForKey:@"keyboardType"];
		_autocapitalizationType = [coder decodeIntegerForKey:@"capitalize"];
	}
	return self;
}

-(instancetype)initWithName:(NSString *)name featureKey:(NSString *)tag defaultValue:(NSString *)defaultValue placeholder:(NSString *)placeholder
				   keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
					presets:(NSArray *)presets
{
	self = [super init];
	if ( self ) {

		if ( placeholder == nil ) {
			if ( presets.count > 1 ) {
				NSMutableString * s = [NSMutableString new];
				for ( NSInteger i = 0; i < 3; ++i ) {
					if ( i >= presets.count )
						break;
					PresetValue * p = presets[i];
					if ( p.name.length >= 20 )
						continue;
					if ( s.length )
						[s appendString:@", "];
					[s appendString:p.name];
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
		_keyboardType	= keyboard;
		_autocapitalizationType = capitalize;
		_presetList		= presets.count ? presets : nil;
		_defaultValue	= defaultValue;
	}
	return self;
}
+(instancetype)presetKeyWithName:(NSString *)name featureKey:(NSString *)tag defaultValue:(NSString *)defaultValue placeholder:(NSString *)placeholder
				  keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
				   presets:(NSArray *)presets
{
	return [[PresetKey alloc] initWithName:name featureKey:tag defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
}

-(NSString *)prettyNameForTagValue:(NSString *)value
{
	for ( PresetValue * presetValue in self.presetList ) {
		if ( [presetValue.tagValue isEqualToString:value] ) {
			return presetValue.name;
		}
	}
	return value;
}
-(NSString *)tagValueForPrettyName:(NSString *)value
{
	for ( PresetValue * presetValue in self.presetList ) {
		NSComparisonResult diff = [presetValue.name compare:value
													options:(NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch)];
		if ( diff == NSOrderedSame ) {
			return presetValue.tagValue;
		}
	}
	return value;
}

-(NSString *)description
{
	return self.name;
}
@end


@implementation PresetGroup
-(instancetype)initWithName:(NSString *)name tags:(NSArray *)tags
{
	self = [super init];
	if ( self ) {
#if DEBUG
		if ( tags.count )	assert( [tags.lastObject isKindOfClass:[PresetKey class]] ||
									[tags.lastObject isKindOfClass:[PresetGroup class]] );	// second case for drill down group
#endif
		_name = name;
		_presetKeys = tags;
	}
	return self;
}
+(instancetype)presetGroupWithName:(NSString *)name tags:(NSArray *)tags
{
	return [[PresetGroup alloc] initWithName:name tags:tags];
}
+(instancetype)presetGroupFromMerger:(PresetGroup *)p1 with:(PresetGroup *)p2
{
	NSArray * merge = p1.presetKeys ? [p1.presetKeys arrayByAddingObjectsFromArray:p2.presetKeys] : p2.presetKeys;
	return [PresetGroup presetGroupWithName:p1.name tags:merge];
}
-(NSString *)description
{
	NSMutableString * text = [NSMutableString new];
	[text appendFormat:@"%@:\n",self.name ?: @"<unnamed>"];
	for ( PresetKey * key in self.presetKeys ) {
		[text appendFormat:@"   %@\n",[key description]];
	}
	return text;
}
@end



@implementation PresetsDatabase(Extension)

+(NSSet *)allTagValuesForKey:(NSString *)key
{
	NSMutableSet * set = [NSMutableSet new];
	[PresetsDatabase.shared.jsonFields enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSString * k = dict[ @"key" ];
		if ( [k isEqualToString:key] ) {
			NSDictionary * dict2 = dict[ @"strings" ];
			NSDictionary * dict3 = dict2[ @"options" ];
			NSArray * a = [dict3 allKeys];
			if ( a.count ) {
				[set addObjectsFromArray:a];
			}
		}
	}];
	[PresetsDatabase.shared enumeratePresetsUsingBlock:^(PresetFeature * feature) {
		NSDictionary * dict2 = feature.tags;
		NSString * value = dict2[ key ];
		if ( value ) {
			[set addObject:value];
		}
	}];
	[set removeObject:@"*"];
	return set;
}

+(NSSet *)allTagKeys
{
	NSMutableSet * set = [NSMutableSet new];
	[PresetsDatabase.shared.jsonFields enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSString * key = dict[ @"key" ];
		if ( key ) {
			[set addObject:key];
		}
		NSDictionary * keys = dict[ @"keys" ];
		for ( key in keys ) {
			[set addObject:key];
		}
	}];
	[PresetsDatabase.shared enumeratePresetsUsingBlock:^(PresetFeature * feature) {
		NSDictionary * dict2 = feature.tags;
		[dict2 enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop2) {
			[set addObject:key];
		}];
	}];
	// these are additionl tags that people might want (e.g. for autocomplete)
	[set addObjectsFromArray:@[
		@"official_name",
		@"alt_name",
		@"short_name",
		@"old_name",
		@"reg_name",
		@"nat_name",
		@"loc_name"
	]];
	return set;
}

+(NSSet<NSString *> *)allFeatureKeys
{
	static NSMutableSet<NSString *> * set = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		set = [NSMutableSet new];
		[PresetsDatabase.shared enumeratePresetsUsingBlock:^(PresetFeature * feature) {
			NSString * featureID = feature.featureID;
			NSRange slash = [feature.featureID rangeOfString:@"/"];
			NSString * featureKey = slash.location != NSNotFound ? [feature.featureID substringToIndex:slash.location] : featureID;
			[set addObject:featureKey];
		}];
	});
	return set;
}


+(NSArray<PresetFeature *> *)featuresAndCategoriesForMemberList:(NSArray *)memberList
{
	NSMutableArray * list = [NSMutableArray new];
	for ( NSString * featureID in memberList ) {

		if ( [featureID hasPrefix:@"category-"] ) {

			PresetCategory * category = [[PresetCategory alloc] initWithCategoryName:featureID];
			[list addObject:category];

		} else {

			PresetFeature * feature = [PresetsDatabase.shared presetFeatureForFeatureID:featureID];
			if ( feature == nil )
				continue;
			[list addObject:feature];

		}
	}
	return list;
}

+(NSArray<PresetFeature *> *)featuresAndCategoriesForGeometry:(NSString *)geometry
{
	NSArray * list = PresetsDatabase.shared.jsonDefaults[geometry];
	NSArray * featureList = [self featuresAndCategoriesForMemberList:list];
	return featureList;
}

+(NSArray<PresetFeature *> *)featuresInCategory:(PresetCategory *)category matching:(NSString *)searchText
{
	NSMutableArray<PresetFeature *> * list = [NSMutableArray new];
	if ( category ) {
		for ( PresetFeature * feature in category.members ) {
			if ( [feature matchesSearchText:searchText] ) {
				[list addObject:feature];
			}
		}
	} else {
		NSString * countryCode = AppDelegate.shared.mapView.countryCodeForLocation;
		NSArray * a = [PresetsDatabase.shared featuresMatchingSearchText:searchText country:countryCode];
		list = [a mutableCopy];
	}
	// sort so that regular items come before suggestions
	[list sortUsingComparator:^NSComparisonResult(PresetFeature * obj1, PresetFeature * obj2) {
		NSString * name1 = obj1.friendlyName;
		NSString * name2 = obj2.friendlyName;
		int diff = obj1.nsiSuggestion - obj2.nsiSuggestion;
		if ( diff )
			return diff;
		// prefer exact matches of primary name over alternate terms
		BOOL p1 = [name1 hasPrefix:searchText];
		BOOL p2 = [name2 hasPrefix:searchText];
		if ( p1 != p2 )
			return p2 - p1;
 		return [name1 compare:name2];
	}];
	return list;
}

+(PresetGroup *)groupForField:(NSString *)fieldName geometry:(NSString *)geometry ignore:(NSArray *)ignore update:(void (^)(void))update
{
	if ( g_taginfoCache == nil ) {
		g_taginfoCache = [NSMutableDictionary new];
	}

	NSDictionary * dict = PresetsDatabase.shared.jsonFields[ fieldName ];
	if ( dict.count == 0 )
		return nil;

	NSArray * geoList = dict[@"geometry"];
	if ( geoList ) {
		if ( ![geoList containsObject:geometry] )
			return nil;
	}

	NSString	*	key					= dict[ @"key" ] ?: fieldName;
	NSString	*	type				= dict[ @"type" ];
	NSArray		*	keysArray			= dict[ @"keys" ];
	NSString	*	label				= dict[ @"label" ];
	NSString	*	placeholder			= dict[ @"placeholder" ];
	NSDictionary *	stringsOptionsDict	= dict[ @"strings" ][ @"options" ];
	NSDictionary*	stringsTypesDict	= dict[ @"strings" ][ @"types" ];
	NSArray		*	optionsArray		= dict[ @"options" ];
	NSString	*	defaultValue		= dict[ @"default" ];
#if TARGET_OS_IPHONE
	UIKeyboardType					keyboard = UIKeyboardTypeDefault;
	UITextAutocapitalizationType	capitalize = [key hasPrefix:@"name:"] || [key isEqualToString:@"operator"] ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeNone;
#else
	int keyboard = 0;
	const int UITextAutocapitalizationTypeNone = 0;
	const int UITextAutocapitalizationTypeWords = 1;
	int	capitalize = [key hasPrefix:@"name:"] || [key isEqualToString:@"operator"] ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeNone;
#endif

//r	DLog(@"%@",dict);

	if ( [type isEqualToString:@"defaultcheck"] || [type isEqualToString:@"check"] || [type isEqualToString:@"onewayCheck"] ) {

		NSArray * presets = @[ [PresetValue presetValueWithName:PresetsDatabase.shared.yesForLocale details:nil tagValue:@"yes"],
							   [PresetValue presetValueWithName:PresetsDatabase.shared.noForLocale  details:nil tagValue:@"no"] ];
		PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
		PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"radio"] || [type isEqualToString:@"structureRadio"] ) {

		if ( keysArray ) {

			// a list of booleans
			NSMutableArray * tags = [NSMutableArray new];
			NSArray * presets = @[ [PresetValue presetValueWithName:PresetsDatabase.shared.yesForLocale details:nil tagValue:@"yes"],
								   [PresetValue presetValueWithName:PresetsDatabase.shared.noForLocale details:nil tagValue:@"no"] ];
			for ( NSString * k in keysArray ) {
				NSString * name = stringsOptionsDict[ k ];
				PresetKey * tag = [PresetKey presetKeyWithName:name featureKey:k defaultValue:defaultValue placeholder:nil keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
				[tags addObject:tag];
			}
			PresetGroup * group = [PresetGroup presetGroupWithName:label tags:tags];
			return group;

		} else if ( optionsArray ) {

			// a multiple selection
			NSMutableArray * presets = [NSMutableArray new];
			for ( NSString * v in optionsArray ) {
				[presets addObject:[PresetValue presetValueWithName:nil details:nil tagValue:v]];
			}
			PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[ tag ]];
			return group;

		} else if ( stringsOptionsDict ) {

			// a multiple selection
			NSMutableArray * presets = [NSMutableArray new];
			[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull val2, NSString * _Nonnull prettyName, BOOL * _Nonnull stop) {
				[presets addObject:[PresetValue presetValueWithName:prettyName details:nil tagValue:val2]];
			}];
			PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[ tag ]];
			return group;

		} else {
#if DEBUG
			assert(NO);
#endif
			return nil;
		}

	} else if ( [type isEqualToString:@"radio"] || [type isEqualToString:@"structureRadio"] ) {
		
		if ( keysArray ) {
			
			// a list of booleans
			NSMutableArray * tags = [NSMutableArray new];
			NSArray * presets = @[ [PresetValue presetValueWithName:PresetsDatabase.shared.yesForLocale details:nil tagValue:@"yes"],
								   [PresetValue presetValueWithName:PresetsDatabase.shared.noForLocale  details:nil tagValue:@"no"] ];
			for ( NSString * k in keysArray ) {
				NSString * name = stringsOptionsDict[ k ];
				PresetKey * tag = [PresetKey presetKeyWithName:name featureKey:k defaultValue:defaultValue placeholder:nil keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
				[tags addObject:tag];
			}
			PresetGroup * group = [PresetGroup presetGroupWithName:label tags:tags];
			return group;
			
		} else if ( optionsArray ) {
			
			// a multiple selection
			NSMutableArray * presets = [NSMutableArray new];
			for ( NSString * v in optionsArray ) {
				[presets addObject:[PresetValue presetValueWithName:nil details:nil tagValue:v]];
			}
			PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[ tag ]];
			return group;
			
		} else {
#if DEBUG
			assert(NO);
#endif
			return nil;
		}

	} else if ( [type isEqualToString:@"combo"] ||
			    [type isEqualToString:@"semiCombo"] || 	// semiCombo is for setting semicolor delimited lists of values, which we don't support
			    [type isEqualToString:@"multiCombo"] ||
			    [type isEqualToString:@"typeCombo"] ||
			    [type isEqualToString:@"manyCombo"] )
	{
		if ( [type isEqualToString:@"typeCombo"] && [ignore containsObject:key] ) {
			return nil;
		}
		BOOL isMulti = [type isEqualToString:@"multiCombo"];
		if ( isMulti && ![key hasSuffix:@":"] )
			key = [key stringByAppendingString:@":"];
		NSMutableArray * presets = [NSMutableArray new];
		if ( stringsOptionsDict ) {

			[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
				[presets addObject:[PresetValue presetValueWithName:v details:nil tagValue:k]];
			}];
			[presets sortUsingComparator:^NSComparisonResult(PresetValue * obj1, PresetValue * obj2) {
				return [obj1.name compare:obj2.name];
			}];

		} else if ( optionsArray ) {

			for ( NSString * v in optionsArray ) {
				[presets addObject:[PresetValue presetValueWithName:nil details:nil tagValue:v]];
			}

		} else {

			// check tagInfo
			if ( g_taginfoCache[ fieldName ] ) {
				// already got them once
				presets = g_taginfoCache[fieldName];
				if ( [presets isKindOfClass:[PresetGroup class]] ) {
					return (PresetGroup *)presets;	// hack for multi-combo: we already created the group and stashed it in presets
				} else {
					// its an array, and we'll convert it to a group below
				}
			} else if ( update ) {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
					NSString * cleanKey = isMulti ? [key stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]] : key;
					NSString * urlText = isMulti ?
						[NSString stringWithFormat:@"https://taginfo.openstreetmap.org/api/4/keys/all?query=%@&filter=characters_colon&page=1&rp=10&sortname=count_all&sortorder=desc", cleanKey] :
						[NSString stringWithFormat:@"https://taginfo.openstreetmap.org/api/4/key/values?key=%@&page=1&rp=25&sortname=count_all&sortorder=desc", key];
					NSURL * url = [NSURL URLWithString:urlText];
					NSData * data = [NSData dataWithContentsOfURL:url];
					if ( data ) {
						NSMutableArray * presets2 = [NSMutableArray new];
						NSDictionary * dict2 = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
						NSArray * values = dict2[@"data"];
						if ( isMulti ) {
							// a list of booleans
							NSMutableArray * tags = [NSMutableArray new];
							NSArray * yesNo = @[ [PresetValue presetValueWithName:PresetsDatabase.shared.yesForLocale details:nil tagValue:@"yes"],
											     [PresetValue presetValueWithName:PresetsDatabase.shared.noForLocale  details:nil tagValue:@"no"] ];
							for ( NSDictionary * v in values ) {
								if ( [v[@"count_all"] integerValue] < 1000 )
									continue; // it's a very uncommon value, so ignore it
								NSString * k = v[@"key"];
								NSString * name = k;
								PresetKey * tag = [PresetKey presetKeyWithName:name featureKey:k defaultValue:defaultValue placeholder:nil keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:yesNo];
								[tags addObject:tag];
							}
							PresetGroup * group = [PresetGroup presetGroupWithName:label tags:tags];
							PresetGroup * group2 = [PresetGroup presetGroupWithName:nil tags:@[group]];
							group.isDrillDown = YES;
							group2.isDrillDown = YES;
							presets2 = (id)group2;

						} else {

							for ( NSDictionary * v in values ) {
								if ( [v[@"fraction"] doubleValue] < 0.01 )
									continue; // it's a very uncommon value, so ignore it
								NSString * val = v[@"value"];
								[presets2 addObject:[PresetValue presetValueWithName:nil details:nil tagValue:val]];
							}
						}
						dispatch_async(dispatch_get_main_queue(), ^{
							[g_taginfoCache setObject:presets2 forKey:fieldName];
							update();
						});
					}
				});
			} else {
				// already submitted to network, so don't do it again
			}
		}

		if ( isMulti ) {
			PresetGroup * group = [PresetGroup presetGroupWithName:label tags:@[]];
			PresetGroup * group2 = [PresetGroup presetGroupWithName:nil tags:@[group]];
			group.isDrillDown = YES;
			group2.isDrillDown = YES;
			return group2;
		} else {
			PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[ tag ]];
			return group;
		}

	} else if ( [type isEqualToString:@"cycleway"] ) {

		NSMutableArray * tagList = [NSMutableArray new];

		for ( key in keysArray ) {

			NSMutableArray * presets = [NSMutableArray new];
			[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSDictionary * v, BOOL *stop) {
				NSString * n = v[@"title"];
				NSString * d = v[@"description"];
				[presets addObject:[PresetValue presetValueWithName:n details:d tagValue:k]];
			}];
			NSString * name = stringsTypesDict[key];
			if ( name == nil )
				name = PrettyTag(type);
			PresetKey * tag = [PresetKey presetKeyWithName:name featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			[tagList addObject:tag];
		}

		PresetGroup * group = [PresetGroup presetGroupWithName:label tags:tagList];
		return group;

	} else if ( [type isEqualToString:@"address"] ) {

		NSString * addressPrefix = dict[@"key"];
		NSArray * numericFields = @[
									@"block_number",
									@"conscriptionnumber",
									@"floor",
									@"housenumber",
									@"postcode",
									@"unit"
									];

		NSString * countryCode = AppDelegate.shared.mapView.countryCodeForLocation;
		NSArray * keysForCountry = nil;
		for ( NSDictionary * localeDict in PresetsDatabase.shared.jsonAddressFormats ) {
			NSArray * countryCodeList = localeDict[@"countryCodes"];
			if ( countryCodeList == nil ) {
				// default
				keysForCountry = localeDict[ @"format" ];
			} else if ( [countryCodeList containsObject:countryCode] ) {
				// country specific format
				keysForCountry = localeDict[ @"format" ];
				break;
			}
		}

		NSDictionary * placeholders = dict[ @"strings" ][ @"placeholders" ];
		NSMutableArray * addrs = [NSMutableArray new];
		for ( NSArray * addressGroup in keysForCountry ) {
			for ( NSString * addressKey in addressGroup ) {
				NSString * name;
				placeholder = placeholders[addressKey];
				if ( placeholder && ![placeholder isEqualToString:@"123"] ) {
					name = placeholder;
				} else {
					name = PrettyTag( addressKey );
				}
				keyboard = [numericFields containsObject:addressKey] ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
				NSString * tagKey = [NSString stringWithFormat:@"%@:%@", addressPrefix, addressKey];
				PresetKey * tag = [PresetKey presetKeyWithName:name featureKey:tagKey defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeWords presets:nil];
				[addrs addObject:tag];
			}
		}
		PresetGroup * group = [PresetGroup presetGroupWithName:label tags:addrs];
		return group;

	} else if ( [type isEqualToString:@"text"] ||
			    [type isEqualToString:@"number"] ||
			    [type isEqualToString:@"email"] ||
			    [type isEqualToString:@"identifier"] ||
			    [type isEqualToString:@"textarea"] ||
			    [type isEqualToString:@"tel"] ||
			    [type isEqualToString:@"url"] ||
			    [type isEqualToString:@"roadspeed"] ||
			    [type isEqualToString:@"wikipedia"] ||
				[type isEqualToString:@"wikidata"] )
	{

		// no presets
		if ( [type isEqualToString:@"number"] || [type isEqualToString:@"roadspeed"])
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypeDecimalPad doesn't have Done button
		else if ( [type isEqualToString:@"tel"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypePhonePad doesn't have Done Button
		else if ( [type isEqualToString:@"url"] )
			keyboard = UIKeyboardTypeURL;
		else if ( [ type isEqualToString:@"email"] )
			keyboard = UIKeyboardTypeEmailAddress;
		else if ( [type isEqualToString:@"textarea"] )
			capitalize = UITextAutocapitalizationTypeSentences;
		PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"access"] ) {

		// special case
		NSMutableArray * presets = [NSMutableArray new];
		[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSDictionary * info, BOOL * stop) {
			PresetValue * v = [PresetValue presetValueWithName:info[@"title"] details:info[@"description"] tagValue:k];
			[presets addObject:v];
		}];

		NSMutableArray * tags = [NSMutableArray new];
		for ( NSString * k in keysArray ) {
			NSString * name = stringsTypesDict[ k ];
			PresetKey * tag = [PresetKey presetKeyWithName:name featureKey:k defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
			[tags addObject:tag];
		}
		PresetGroup * group = [PresetGroup presetGroupWithName:label tags:tags];
		return group;

	} else if ( [type isEqualToString:@"localized"] ) {

		// not implemented
		return nil;

	} else {

#if DEBUG
		assert(NO);
#endif
		PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[tag]];
		return group;

	}
}



+(BOOL)isArea:(OsmWay *)way
{
	static NSDictionary * areaTags = nil;
	if ( areaTags == nil ) {

		// make a list of items that can/cannot be areas
		NSMutableDictionary * areaKeys = [NSMutableDictionary new];
		NSArray * ignore = @[ @"barrier", @"highway", @"footway", @"railway", @"type" ];

		// whitelist
		[PresetsDatabase.shared enumeratePresetsUsingBlock:^(PresetFeature * feature) {
			if ( feature.nsiSuggestion )
				return;
			NSArray * geom = feature.geometry;
			if ( ![geom containsObject:@"area"] )
				return;
			NSDictionary * tags = feature.tags;
			if ( tags.count > 1 )
				return;	// very specific tags aren't suitable for whitelist, since we don't know which key is primary (in iD the JSON order is preserved and it would be the first key)
			for ( NSString * key in tags ) {
				if ( [ignore containsObject:key] )
					return;
				[areaKeys setObject:[NSMutableDictionary new] forKey:key];
			}
		}];

		// blacklist
		[PresetsDatabase.shared enumeratePresetsUsingBlock:^(PresetFeature * feature) {
			if ( feature.nsiSuggestion )
				return;
			NSArray * geom = feature.geometry;
			if ( [geom containsObject:@"area"] )
				return;
			NSDictionary * tags = feature.tags;
			for ( NSString * key in tags ) {
				if ( [ignore containsObject:key] )
					return;
				NSString * value = tags[key];
				if ( areaKeys[key] != nil  &&  ![value isEqualToString:@"*"] ) {
					NSMutableDictionary * d = areaKeys[key];
					d[value] = @true;
				}
			}
		}];

		areaTags = areaKeys;
	}
	
	NSString * value = way.tags[@"area"];
	if ( value && IsOsmBooleanTrue(value) )
		return YES;
	if ( !way.isClosed )
		return NO;
	if ( value && IsOsmBooleanFalse(value) )
		return NO;
	if ( way.tags.count == 0 )
		return YES;	// newly created closed way
	__block BOOL area = NO;
	[way.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * val, BOOL *stop) {
		NSDictionary * exclusions = areaTags[key];
		if ( exclusions && !exclusions[val] ) {
			area = YES;
			*stop = YES;
		}
	}];
	return area;
}

+(BOOL)eligibleForAutocomplete:(NSString *)key
{
	static NSDictionary * list = nil;
	if ( list == nil ) {
		list = @{
			@"capacity" : @(YES),
			@"depth" : @(YES),
			@"ele" : @(YES),
			@"height" : @(YES),
			@"housenumber" : @(YES),
			@"lanes" : @(YES),
			// @"layer" : @(YES),
			@"maxspeed" : @(YES),
			@"maxweight" : @(YES),
			@"scale" : @(YES),
			@"step_count" : @(YES),
			@"unit" : @(YES),
			@"width" : @(YES),
		};
	}
	if ( list[key] != nil )
		return NO;
	__block BOOL isBad = NO;
	[list enumerateKeysAndObjectsUsingBlock:^(NSString * suffix, NSNumber * isSuffix, BOOL * stop) {
		if ( isSuffix.boolValue && [key hasSuffix:suffix] ) {
			if ( [key characterAtIndex:key.length-suffix.length-1] == ':' ) {
				isBad = YES;
				*stop = YES;
			}
		}
	}];
	return !isBad;
}

@end



@implementation CustomPreset
-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)key placeholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize presets:(NSArray *)presets
{
	return [super initWithName:name featureKey:key defaultValue:nil placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
}
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)key placeholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize presets:(NSArray *)presets
{
	return [[CustomPreset alloc] initWithName:name tagKey:key placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
}
-(void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeObject:_appliesToKey forKey:@"appliesToKey"];
	[coder encodeObject:_appliesToValue forKey:@"appliesToValue"];
}
-(instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if ( self ) {
		_appliesToKey = [coder decodeObjectForKey:@"appliesToKey"];
		_appliesToValue = [coder decodeObjectForKey:@"appliesToValue"];
	}
	return self;
}
@end


@implementation CustomPresetList

+(instancetype)shared
{
	static CustomPresetList * list;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		list = [CustomPresetList new];
		[list load];
	});
	return list;
}

+(NSString *)archivePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *cacheDirectory = [paths objectAtIndex:0];
	NSString *fullPath = [cacheDirectory stringByAppendingPathComponent:@"CustomPresetList.data"];
	return fullPath;
}

-(void)load
{
	@try {	// some people experience a crash during loading...
		NSString * path = [CustomPresetList archivePath];
		_list = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
	} @catch ( id exception ) {
		NSLog(@"error loading custom presets");
	}
	if ( _list == nil ) {
		_list = [NSMutableArray new];
	}
}

-(void)save
{
	NSString * path = [CustomPresetList archivePath];
	[NSKeyedArchiver archiveRootObject:_list toFile:path];
}

-(NSInteger)count
{
	return _list.count;
}

-(CustomPreset *)presetAtIndex:(NSUInteger)index
{
	return [_list objectAtIndex:index];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len;
{
	return [_list countByEnumeratingWithState:state objects:buffer count:len];
}

-(void)addPreset:(CustomPreset *)preset atIndex:(NSInteger)index
{
	[_list insertObject:preset atIndex:index];
}

-(void)removePresetAtIndex:(NSInteger)index
{
	[_list removeObjectAtIndex:index];
}

@end



@implementation PresetCategory
-(instancetype)initWithCategoryName:(NSString *)name;
{
	self = [super init];
	if ( self ) {
		_categoryName = name;
	}
	return self;
}
-(NSString	*)friendlyName
{
	NSDictionary * dict = PresetsDatabase.shared.jsonCategories[ _categoryName ];
	return dict[ @"name" ];
}
-(UIImage *)icon
{
	return nil;
}
-(NSArray<PresetFeature *> *)members
{
	NSDictionary * dict = PresetsDatabase.shared.jsonCategories[ _categoryName ];
	NSArray<PresetFeature *> * m = dict[ @"members" ];
	NSMutableArray<PresetFeature *> * m2 = [NSMutableArray new];
	for ( NSString * p in m ) {
		PresetFeature * t = [PresetsDatabase.shared presetFeatureForFeatureID:p];
		if ( p ) {
			[m2 addObject:t];
		}
	}
	return m2;
}
@end



@implementation PresetsForFeature

+(instancetype)presetsForFeature:(PresetFeature *)feature objectTags:(NSDictionary *)objectTags geometry:(NSString *)geometry  update:(void (^)(void))update
{
	PresetsForFeature * presentation = [PresetsForFeature new];
	[presentation setFeature:feature
				  objectTags:objectTags
					geometry:geometry
					  update:update];
	return presentation;
}

-(NSString *)featureName
{
	return _featureName;
}
-(NSArray *)sectionList
{
	return _sectionList;
}

-(NSInteger)sectionCount
{
	return _sectionList.count;
}

-(PresetGroup *)groupAtIndex:(NSInteger)index
{
	return _sectionList[ index ];
}

-(NSInteger)tagsInSection:(NSInteger)index
{
	PresetGroup * group = _sectionList[ index ];
	return group.presetKeys.count;
}

-(PresetKey *)presetAtSection:(NSInteger)section row:(NSInteger)row
{
	PresetGroup * group = _sectionList[ section ];
	PresetKey * tag = group.presetKeys[ row ];
	return tag;
}

-(PresetKey *)presetAtIndexPath:(NSIndexPath *)indexPath
{
	return [self presetAtSection:indexPath.section row:indexPath.row];
}

-(void)addPresetsForFieldsInFeatureID:(NSString *)featureID
							 geometry:(NSString *)geometry
								field:(NSArray * (^)(PresetFeature * feature))valueGetter
							   ignore:(NSArray *)ignore
							   dupSet:(NSMutableSet *)dupSet
							   update:(void (^)(void))update
{
	NSArray * fields = (id)[PresetsDatabase.shared inheritedValueOfFeature:featureID valueGetter:valueGetter];

	for ( NSString * field in fields ) {

		if ( [field hasPrefix:@"{"] && [field hasSuffix:@"}"]) {
			// copy fields from referenced item
			NSString * refFeature = [field substringWithRange:NSMakeRange(1, field.length-2)];
			[self addPresetsForFieldsInFeatureID:refFeature
										geometry:geometry
										   field:valueGetter
										  ignore:ignore
										  dupSet:dupSet
										  update:update];
			continue;
		}

		if ( [dupSet containsObject:field] )
			continue;
		[dupSet addObject:field];

		PresetGroup * group = [PresetsDatabase groupForField:field geometry:geometry ignore:ignore update:update];
		if ( group == nil )
			continue;
		// if both this group and the previous don't have a name then merge them
		if ( (group.name == nil || group.isDrillDown) && _sectionList.count > 1 ) {
			PresetGroup * prev = _sectionList.lastObject;
			if ( prev.name == nil ) {
				prev = [PresetGroup presetGroupFromMerger:prev with:group];
				[_sectionList removeLastObject];
				[_sectionList addObject:prev];
				continue;
			}
		}
		[_sectionList addObject:group];
	}
}

-(void)setFeature:(PresetFeature *)feature objectTags:(NSDictionary *)objectTags geometry:(NSString *)geometry update:(void (^)(void))update
{
	_featureName = feature.name;

	// Always start with Type and Name
	PresetKey * typeTag = [PresetKey presetKeyWithName:@"Type"
											featureKey:nil
										  defaultValue:nil
										   placeholder:@""
											  keyboard:UIKeyboardTypeDefault
											capitalize:UITextAutocapitalizationTypeNone
											   presets:@[@"",@""]];
	PresetKey * nameTag = [PresetKey presetKeyWithName:PresetsDatabase.shared.jsonFields[@"name"][@"label"]
											featureKey:@"name"
										  defaultValue:nil
										   placeholder:PresetsDatabase.shared.jsonFields[@"name"][@"placeholder"]
											  keyboard:UIKeyboardTypeDefault
											capitalize:UITextAutocapitalizationTypeWords
											   presets:nil];
	PresetGroup * typeGroup = [PresetGroup presetGroupWithName:@"Type" tags:@[ typeTag, nameTag ] ];
	_sectionList = [NSMutableArray arrayWithArray:@[ typeGroup ]];

	// Add user-defined presets
	NSMutableArray * customGroup = [NSMutableArray new];
	for ( CustomPreset * custom in [CustomPresetList shared] ) {
		if ( custom.appliesToKey.length ) {
			NSString * v = objectTags[ custom.appliesToKey ];
			if ( v && (custom.appliesToValue.length == 0 || [v isEqualToString:custom.appliesToValue]) ) {
				// accept
			} else {
				continue;
			}
		}
		[customGroup addObject:custom];
	}
	if ( customGroup.count ) {
		PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:customGroup];
		[_sectionList addObject:group];
	}

	// Add presets specific to the type
	NSMutableSet * dupSet = [NSMutableSet new];
	NSArray * ignoreTags = [feature.tags allKeys];
	[self addPresetsForFieldsInFeatureID:feature.featureID
							  geometry:geometry
								 field:^(PresetFeature * f){return f.fields;}
								ignore:ignoreTags
								dupSet:dupSet
								update:update];
	[_sectionList addObject:[PresetGroup presetGroupWithName:nil tags:nil]];	// Create a break between the common items and the rare items
	[self addPresetsForFieldsInFeatureID:feature.featureID
							  geometry:geometry
								 field:^(PresetFeature * f){return f.moreFields;}
								ignore:ignoreTags
								dupSet:dupSet
								update:update];
}
@end



@implementation PresetFeature(Extension)

-(NSDictionary *)defaultValuesForGeometry:(NSString *)geometry
{
	NSMutableDictionary * result = nil;
	for ( NSString * field in self.fields ) {
		NSDictionary * fieldDict = PresetsDatabase.shared.jsonFields[ field ];
		NSString * value = fieldDict[ @"default" ];
		if ( value == nil )
			continue;
		NSString * key = fieldDict[ @"key" ];
		if ( key == nil )
			continue;
		NSArray * geom = fieldDict[@"geometry"];
		if ( geom && ![geom containsObject:geometry] )
			continue;
		if ( result == nil )
			result = [NSMutableDictionary dictionaryWithObject:value forKey:key];
		else
			[result setObject:value forKey:key];
	}
	return result;
}

@end

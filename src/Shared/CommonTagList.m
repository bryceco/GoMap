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
#import "CommonTagList.h"
#import "DLog.h"
#import "TagInfo.h"

#define USE_SUGGESTIONS	1

#if !TARGET_OS_IPHONE
const int UIKeyboardTypeDefault					= 0;
const int UIKeyboardTypeNumbersAndPunctuation 	= 1;
const int UIKeyboardTypeURL						= 2;

const int UITextAutocapitalizationTypeNone		= 0;
const int UITextAutocapitalizationTypeSentences = 1;
const int UITextAutocapitalizationTypeWords		= 2;
#endif

static NSDictionary * g_addressFormatsDict;
static NSDictionary * g_defaultsDict;
static NSDictionary * g_categoriesDict;
static NSDictionary * g_presetsDict;
static NSDictionary * g_fieldsDict;
static NSDictionary * g_translationDict;
static NSMutableDictionary 	* g_taginfoCache;
static NSMutableDictionary 	* g_FeatureRepository;

static NSDictionary * DictionaryForFile( NSString * file )
{
	NSString * rootDir = [[NSBundle mainBundle] resourcePath];
	NSString * rootPresetPath = [NSString stringWithFormat:@"%@/presets/%@",rootDir,file];
	NSData * rootPresetData = [NSData dataWithContentsOfFile:rootPresetPath];
	if ( rootPresetData == nil )
		return nil;
	NSDictionary * dict = [NSJSONSerialization JSONObjectWithData:rootPresetData options:0 error:NULL];
	DbgAssert(dict);
	return dict;
}

static id Translate( id orig, id translation )
{
	if ( translation == nil )
		return orig;
	if ( [orig isKindOfClass:[NSString class]] && [translation isKindOfClass:[NSString class]] ) {
		if ( [translation hasPrefix:@"<"] )
			return orig; // meta content
		return translation;
	}
	if ( [orig isKindOfClass:[NSArray class]] ) {
		if ( [translation isKindOfClass:[NSDictionary class]] ) {
			NSArray			* origArray = orig;
			NSMutableArray	* newArray = [NSMutableArray arrayWithCapacity:origArray.count];
			for ( NSInteger i = 0; i < origArray.count; ++i ) {
				id o = [translation objectForKey:@(i)] ?: origArray[ i ];
				[newArray addObject:o];
			}
			return newArray;
		} else if ( [translation isKindOfClass:[NSString class]] ) {
			NSArray * a = [translation componentsSeparatedByString:@","];
			return a;
		} else {
			return orig;
		}
	}
	if ( [orig isKindOfClass:[NSDictionary class]] && [translation isKindOfClass:[NSDictionary class]] ) {
		NSMutableDictionary * newDict = [ NSMutableDictionary new];
		[orig enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			if ( [key isEqualToString:@"strings"] ) {
				// for "strings" the translation skips a level
				newDict[key] = Translate( obj, translation );
			} else {
				newDict[key] = Translate( obj, translation[key] );
			}
		}];
		return newDict;
	}
	return orig;
}

static void InitializeDictionaries()
{
	if ( g_presetsDict == nil ) {
		g_addressFormatsDict = DictionaryForFile(@"address-formats.json");

		g_defaultsDict		= DictionaryForFile(@"defaults.json");
		g_categoriesDict	= DictionaryForFile(@"categories.json");
		g_presetsDict		= DictionaryForFile(@"presets.json");
		g_fieldsDict		= DictionaryForFile(@"fields.json");

		PresetLanguages * presetLanguages = [PresetLanguages new];	// don't need to save this, it doesn't get used again unless user changes the language
		NSString * code = presetLanguages.preferredLanguageCode;
		NSString * code2 = [code stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
		NSString * file = [NSString stringWithFormat:@"translations/%@.json",code];
		g_translationDict	= DictionaryForFile(file);
		g_translationDict	= g_translationDict[ code2 ][ @"presets" ];

		g_defaultsDict		= Translate( g_defaultsDict,	g_translationDict[@"defaults"] );
		g_categoriesDict	= Translate( g_categoriesDict,	g_translationDict[@"categories"] );
		g_presetsDict		= Translate( g_presetsDict,		g_translationDict[@"presets"] );
		g_fieldsDict		= Translate( g_fieldsDict,		g_translationDict[@"fields"] );
	}
}

static NSString * PrettyTag( NSString * tag )
{
	tag = [tag stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	tag = [tag capitalizedString];
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

@implementation CommonTagValue
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
+(instancetype)presetWithName:(NSString *)name details:(NSString *)details tagValue:(NSString *)value
{
	return [[CommonTagValue alloc] initWithName:name details:details tagValue:value];
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
@end




@implementation CommonTagGroup
-(instancetype)initWithName:(NSString *)name tags:(NSArray *)tags
{
	self = [super init];
	if ( self ) {
#if DEBUG
		if ( tags.count )	assert( [tags.lastObject isKindOfClass:[CommonTagKey class]] ||
								   [tags.lastObject isKindOfClass:[CommonTagGroup class]] );	// second case for drill down group
#endif
		_name = name;
		_tags = tags;
	}
	return self;
}
+(instancetype)groupWithName:(NSString *)name tags:(NSArray *)tags
{
	return [[CommonTagGroup alloc] initWithName:name tags:tags];
}
-(void)mergeTagsFromGroup:(CommonTagGroup *)other
{
	if ( _tags == nil )
		_tags = other.tags;
	else
		_tags = [_tags arrayByAddingObjectsFromArray:other.tags];
}
@end


@implementation CommonTagKey
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

-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)tag defaultValue:(NSString *)defaultValue placeholder:(NSString *)placeholder
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
					CommonTagValue * p = presets[i];
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
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)tag defaultValue:(NSString *)defaultValue placeholder:(NSString *)placeholder
				  keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
				   presets:(NSArray *)presets
{
	return [[CommonTagKey alloc] initWithName:name tagKey:tag defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
}
@end


@implementation CommonTagList

+(void)initialize
{
	g_presetsDict		= nil;
	g_taginfoCache		= nil;
	g_FeatureRepository	= nil;
	InitializeDictionaries();
}

+(instancetype)sharedList
{
	static dispatch_once_t onceToken;
	static CommonTagList * list = nil;
	dispatch_once(&onceToken, ^{
		InitializeDictionaries();
		list = [CommonTagList new];
	});
	return list;
}

+(NSString *)friendlyValueNameForKey:(NSString *)key value:(NSString *)value geometry:(NSString *)geometry
{
	__block BOOL makePretty = NO;
	[g_fieldsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSString * k = dict[ @"key" ];
		if ( [k isEqualToString:key] ) {
			NSString * type = dict[ @"type" ];
			if ( [type isEqualToString:@"defaultcheck"] ||
				 [type isEqualToString:@"check"] ||
				 [type isEqualToString:@"radio"] ||
				 [type isEqualToString:@"combo"] ||
				 [type isEqualToString:@"typeCombo"] )
			{
				makePretty = YES;
			}
			*stop = YES;
		}
	}];
	if ( makePretty )
		return PrettyTag( value );
	return value;
}

+(NSSet *)allTagValuesForKey:(NSString *)key
{
	NSMutableSet * set = [NSMutableSet new];
	[g_fieldsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
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
	[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSDictionary * dict2 = dict[ @"tags" ];
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
	[g_fieldsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSString * key = dict[ @"key" ];
		if ( key ) {
			[set addObject:key];
		}
		NSDictionary * keys = dict[ @"keys" ];
		for ( key in keys ) {
			[set addObject:key];
		}
	}];
	[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSDictionary * dict2 = dict[ @"tags" ];
		[dict2 enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop2) {
			[set addObject:key];
		}];
	}];
	return set;
}



+(NSArray *)featuresForMembersList:(NSArray *)memberList
{
	NSMutableArray * list = [NSMutableArray new];
	for ( NSString * featureName in memberList ) {

		if ( [featureName hasPrefix:@"category-"] ) {

			CommonTagCategory * category = [[CommonTagCategory alloc] initWithCategoryName:featureName];
			[list addObject:category];

		} else {

			CommonTagFeature * tag = [CommonTagFeature commonTagFeatureWithName:featureName];
			if ( tag == nil )
				continue;
			[list addObject:tag];

		}
	}
	return list;
}

+(NSArray *)featuresForGeometry:(NSString *)geometry
{
	NSArray * list = g_defaultsDict[geometry];
	NSArray * featureList = [self featuresForMembersList:list];
	return featureList;
}

+(NSArray *)featuresInCategory:(CommonTagCategory *)category matching:(NSString *)searchText;
{
	NSMutableArray * list = [NSMutableArray new];
	if ( category ) {
		for ( CommonTagFeature * tag in category.members ) {
			if ( [tag matchesSearchText:searchText] ) {
				[list addObject:tag];
			}
		}
	} else {
		NSString * countryCode = [AppDelegate getAppDelegate].mapView.countryCodeForLocation;
		[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * featureName, NSDictionary * dict, BOOL *stop) {
#if USE_SUGGESTIONS
			NSArray<NSString *> * a = dict[@"countryCodes"];
			BOOL found = NO;
			for ( NSString * s in a ) {
				if ( [countryCode isEqualToString:s] ) {
					found = YES;
					break;
				}
			}
			if ( !found )
				return;
#else
			if ( dict[@"suggestion"] )
				return;
#endif
			id searchable = dict[@"searchable"];
			if ( searchable && [searchable boolValue] == NO )
				return;

			BOOL add = NO;
			if ( [featureName rangeOfString:searchText options:NSCaseInsensitiveSearch].length > 0 ) {
				add = YES;
			} else if ( [dict[@"name"] rangeOfString:searchText options:NSCaseInsensitiveSearch].length > 0 ) {
				add = YES;
			} else {
				for ( NSString * term in dict[ @"terms" ] ) {
					if ( [term rangeOfString:searchText options:NSCaseInsensitiveSearch].length > 0 ) {
						add = YES;
						break;
					}
				}
			}
			if ( add ) {
				CommonTagFeature * tag = [CommonTagFeature commonTagFeatureWithName:featureName];
				if ( tag ) {
					[list addObject:tag];
				}
			}
		}];
	}
	return list;
}

+(NSString *)yesForLocale
{
	NSDictionary * dict = g_translationDict[@"fields"][@"internet_access"][@"options"];
	NSString * text = dict[ @"yes" ];
	if ( text == nil )
		text = @"Yes";
	return text;
}
+(NSString *)noForLocale
{
	NSDictionary * dict = g_translationDict[@"fields"][@"internet_access"][@"options"];
	NSString * text = dict[ @"no" ];
	if ( text == nil )
		text = @"No";
	return text;
}

-(NSString *)featureName
{
	return _featureName;
}

-(CommonTagGroup *)groupForField:(NSString *)fieldName geometry:(NSString *)geometry update:(void (^)(void))update
{
	if ( g_taginfoCache == nil ) {
		g_taginfoCache = [NSMutableDictionary new];
	}

	NSDictionary * dict = g_fieldsDict[ fieldName ];
	if ( dict.count == 0 )
		return nil;

	NSString * geo = dict[@"geometry"];
	if ( geo && [geo rangeOfString:geometry].location == NSNotFound ) {
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

		NSArray * presets = @[ [CommonTagValue presetWithName:[CommonTagList yesForLocale] details:nil tagValue:@"yes"],
							   [CommonTagValue presetWithName:[CommonTagList noForLocale]  details:nil tagValue:@"no"] ];
		CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"radio"] || [type isEqualToString:@"structureRadio"] ) {

		if ( keysArray ) {

			// a list of booleans
			NSMutableArray * tags = [NSMutableArray new];
			NSArray * presets = @[ [CommonTagValue presetWithName:[CommonTagList yesForLocale] details:nil tagValue:@"yes"],
								   [CommonTagValue presetWithName:[CommonTagList noForLocale]  details:nil tagValue:@"no"] ];
			for ( NSString * k in keysArray ) {
				NSString * name = stringsOptionsDict[ k ];
				CommonTagKey * tag = [CommonTagKey tagWithName:name tagKey:k defaultValue:defaultValue placeholder:nil keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
				[tags addObject:tag];
			}
			CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:tags];
			return group;

		} else if ( optionsArray ) {

			// a multiple selection
			NSMutableArray * presets = [NSMutableArray new];
			for ( NSString * v in optionsArray ) {
				[presets addObject:[CommonTagValue presetWithName:nil details:nil tagValue:v]];
			}
			CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
			return group;

		} else if ( stringsOptionsDict ) {

			// a multiple selection
			NSMutableArray * presets = [NSMutableArray new];
			[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key2, NSString * _Nonnull val, BOOL * _Nonnull stop) {
				[presets addObject:[CommonTagValue presetWithName:nil details:nil tagValue:val]];
			}];
			CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
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
			NSArray * presets = @[ [CommonTagValue presetWithName:[CommonTagList yesForLocale] details:nil tagValue:@"yes"],
								   [CommonTagValue presetWithName:[CommonTagList noForLocale]  details:nil tagValue:@"no"] ];
			for ( NSString * k in keysArray ) {
				NSString * name = stringsOptionsDict[ k ];
				CommonTagKey * tag = [CommonTagKey tagWithName:name tagKey:k defaultValue:defaultValue placeholder:nil keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
				[tags addObject:tag];
			}
			CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:tags];
			return group;
			
		} else if ( optionsArray ) {
			
			// a multiple selection
			NSMutableArray * presets = [NSMutableArray new];
			for ( NSString * v in optionsArray ) {
				[presets addObject:[CommonTagValue presetWithName:nil details:nil tagValue:v]];
			}
			CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
			return group;
			
		} else {
#if DEBUG
			assert(NO);
#endif
			return nil;
		}

	} else if ( [type isEqualToString:@"combo"] || [type isEqualToString:@"semiCombo"] || [type isEqualToString:@"multiCombo"] ) {	// semiCombo is for setting semicolor delimited lists of values, which we don't support

		BOOL isMulti = [type isEqualToString:@"multiCombo"];
		if ( isMulti && ![key hasSuffix:@":"] )
			key = [key stringByAppendingString:@":"];
		NSMutableArray * presets = [NSMutableArray new];
		if ( stringsOptionsDict ) {

			[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
				[presets addObject:[CommonTagValue presetWithName:v details:nil tagValue:k]];
			}];
			[presets sortUsingComparator:^NSComparisonResult(CommonTagValue * obj1, CommonTagValue * obj2) {
				return [obj1.name compare:obj2.name];
			}];

		} else if ( optionsArray ) {

			for ( NSString * v in optionsArray ) {
				[presets addObject:[CommonTagValue presetWithName:nil details:nil tagValue:v]];
			}

		} else {

			// check tagInfo
			if ( g_taginfoCache[fieldName] ) {
				// already got them once
				presets = g_taginfoCache[fieldName];
				if ( [presets isKindOfClass:[CommonTagGroup class]] ) {
					return (CommonTagGroup *)presets;	// hack for multi-combo: we already created the group and stashed it in presets
				}
			} else if ( update ) {
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
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
							NSArray * yesNo = @[ [CommonTagValue presetWithName:[CommonTagList yesForLocale] details:nil tagValue:@"yes"],
											     [CommonTagValue presetWithName:[CommonTagList noForLocale]  details:nil tagValue:@"no"] ];
							for ( NSDictionary * v in values ) {
								if ( [v[@"count_all"] integerValue] < 1000 )
									continue; // it's a very uncommon value, so ignore it
								NSString * k = v[@"key"];
								NSString * name = k;
								CommonTagKey * tag = [CommonTagKey tagWithName:name tagKey:k defaultValue:defaultValue placeholder:nil keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:yesNo];
								[tags addObject:tag];
							}
							CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:tags];
							CommonTagGroup * group2 = [CommonTagGroup groupWithName:nil tags:@[group]];
							group.isDrillDown = YES;
							group2.isDrillDown = YES;
							presets2 = (id)group2;

						} else {

							for ( NSDictionary * v in values ) {
								if ( [v[@"fraction"] doubleValue] < 0.01 )
									continue; // it's a very uncommon value, so ignore it
								NSString * val = v[@"value"];
								[presets2 addObject:[CommonTagValue presetWithName:nil details:nil tagValue:val]];
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
			CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:@[]];
			CommonTagGroup * group2 = [CommonTagGroup groupWithName:nil tags:@[group]];
			group.isDrillDown = YES;
			group2.isDrillDown = YES;
			return group2;
		} else {
			CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
			return group;
		}

	} else if ( [type isEqualToString:@"cycleway"] ) {

		NSMutableArray * tagList = [NSMutableArray new];

		for ( key in keysArray ) {

			NSMutableArray * presets = [NSMutableArray new];
			[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSDictionary * v, BOOL *stop) {
				NSString * n = v[@"title"];
				NSString * d = v[@"description"];
				[presets addObject:[CommonTagValue presetWithName:n details:d tagValue:k]];
			}];
			CommonTagKey * tag = [CommonTagKey tagWithName:stringsTypesDict[key] tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
			[tagList addObject:tag];
		}

		CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:tagList];
		return group;

	} else if ( [type isEqualToString:@"address"] ) {

		NSArray * numericFields = @[
									@"addr:block_number",
									@"addr:conscriptionnumber",
									@"addr:floor",
									@"addr:housenumber",
									@"addr:postcode",
									@"addr:unit"
									];

		NSString * countryCode = [AppDelegate getAppDelegate].mapView.countryCodeForLocation;
		NSArray * keys = nil;
		for ( NSDictionary * localeDict in g_addressFormatsDict ) {
			NSArray * countryCodeList = localeDict[@"countryCodes"];
			if ( countryCodeList == nil ) {
				// default
				keys = localeDict[ @"format" ];
			} else if ( [countryCodeList containsObject:countryCode] ) {
				// country specific format
				keys = localeDict[ @"format" ];
				break;
			}
		}

		NSDictionary * placeholders = dict[ @"strings" ][ @"placeholders" ];
		NSMutableArray * addrs = [NSMutableArray new];
		for ( NSArray * row in keys ) {
			for ( NSString * k in row ) {
				NSString * name = k;
				placeholder = placeholders[name];
				name = PrettyTag( name );
				if ( ![placeholder isEqualToString:@"123"] )
					name = placeholder;
				keyboard = [numericFields containsObject:k] ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
				NSString * tagKey = [@"addr:" stringByAppendingString:k];
				CommonTagKey * tag = [CommonTagKey tagWithName:name tagKey:tagKey defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeWords presets:nil];
				[addrs addObject:tag];
			}
		}
		CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:addrs];
		return group;

	} else if ( [type isEqualToString:@"text"] ||
			    [type isEqualToString:@"number"] ||
			    [type isEqualToString:@"email"] ||
			    [type isEqualToString:@"identifier"] ||
			    [type isEqualToString:@"textarea"] ||
			    [type isEqualToString:@"tel"] ||
			    [type isEqualToString:@"url"] ||
			    [type isEqualToString:@"wikipedia"] ||
				[type isEqualToString:@"wikidata"] )
	{

		// no presets
		if ( [type isEqualToString:@"number"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypeDecimalPad doesn't have Done button
		else if ( [type isEqualToString:@"tel"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypePhonePad doesn't have Done Button
		else if ( [type isEqualToString:@"url"] )
			keyboard = UIKeyboardTypeURL;
		else if ( [ type isEqualToString:@"email"] )
			keyboard = UIKeyboardTypeEmailAddress;
		else if ( [type isEqualToString:@"textarea"] )
			capitalize = UITextAutocapitalizationTypeSentences;
		CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"maxspeed"] ) {

		// special case
		CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"access"] ) {

		// special case
		NSMutableArray * presets = [NSMutableArray new];
		[stringsOptionsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSDictionary * info, BOOL * stop) {
			CommonTagValue * v = [CommonTagValue presetWithName:info[@"title"] details:info[@"description"] tagValue:k];
			[presets addObject:v];
		}];

		NSMutableArray * tags = [NSMutableArray new];
		for ( NSString * k in keysArray ) {
			NSString * name = stringsTypesDict[ k ];
			CommonTagKey * tag = [CommonTagKey tagWithName:name tagKey:k defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
			[tags addObject:tag];
		}
		CommonTagGroup * group = [CommonTagGroup groupWithName:label tags:tags];
		return group;

	} else if ( [type isEqualToString:@"typeCombo"] ) {

		// skip since this is for selecting generic objects
		return nil;

	} else if ( [type isEqualToString:@"localized"] ) {

		// not implemented
		return nil;

	} else {

#if DEBUG
		assert(NO);
#endif
		CommonTagKey * tag = [CommonTagKey tagWithName:label tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	}
}

+(NSString *)featureNameForObjectDict:(NSDictionary *)objectTags geometry:(NSString *)geometry
{
	__block double bestMatchScore = 0.0;
	__block NSString * bestMatchName = nil;

	NSString * countryCode = [AppDelegate getAppDelegate].mapView.countryCodeForLocation;

	[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * featureName, NSDictionary * dict, BOOL * stop) {

		__block double totalScore = 0;
#if USE_SUGGESTIONS
		NSArray<NSString *> * a = dict[@"countryCodes"];
		if ( a.count > 0 ) {
			BOOL found = NO;
			for ( NSString * s in a ) {
				if ( [countryCode isEqualToString:s] ) {
					found = YES;
					break;
				}
			}
			if ( !found )
				return;
		}
#else

		id suggestion = dict[@"suggestion"];
		if ( suggestion )
			return;
#endif

		NSArray * geom = dict[@"geometry"];
		for ( NSString * g in geom ) {
			if ( [g isEqualToString:geometry] ) {
				totalScore = 1;
				break;
			}
		}
		if ( totalScore == 0 )
			return;

		NSString * matchScoreText = dict[ @"matchScore" ];
		double matchScore = matchScoreText ? matchScoreText.doubleValue : 1.0;

		NSDictionary * keyvals = dict[ @"tags" ];
		if ( keyvals.count == 0 )
			return;

		NSMutableSet * seen = [NSMutableSet new];
		[keyvals enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop2) {
			[seen addObject:key];

			__block NSString * v = nil;
			if ( [key hasSuffix:@"*"] ) {
				NSString * c = [key stringByReplacingCharactersInRange:NSMakeRange(key.length-1,1) withString:@""];
				[objectTags enumerateKeysAndObjectsUsingBlock:^(NSString * k2, NSString * v2, BOOL * stop3) {
					if ( [k2 hasPrefix:c] ) {
						v = v2;
						*stop3 = YES;
					}
				}];
			} else {
				v = objectTags[ key ];
			}
			if ( v ) {
				if ( [value isEqualToString:v] ) {
					totalScore += matchScore;
					return;
				}
				if ( [value isEqualToString:@"*"] ) {
					totalScore += matchScore/2;
					return;
				}
			}
			totalScore = -1;
			*stop2 = YES;
		}];

		// boost score for additional matches in addTags
		[dict[@"addTags"] enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * _Nonnull val, BOOL *stop3) {
			if ( ![seen containsObject:key] && [objectTags[key] isEqualToString:val] ) {
				totalScore += matchScore;
			}
		}];

		if ( totalScore > bestMatchScore ) {
			bestMatchName = featureName;
			bestMatchScore = totalScore;
		}
	}];
	return bestMatchName;
}



+(BOOL)isArea:(OsmWay *)way
{
	static NSDictionary * areaTags = nil;
	if ( areaTags == nil ) {

		// make a list of items that can/cannot be areas
		NSMutableDictionary * areaKeys = [NSMutableDictionary new];
		NSArray * ignore = @[ @"barrier", @"highway", @"footway", @"railway", @"type" ];

		// whitelist
		[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * field, NSDictionary * dict, BOOL * stop) {
			if ( dict[@"suggestion"] )
				return;
			NSArray * geom = dict[@"geometry"];
			if ( ![geom containsObject:@"area"] )
				return;
			NSDictionary * tags = dict[@"tags"];
			if ( tags.count > 1 )
				return;	// very specific tags aren't suitable for whitelist, since we don't know which key is primary (in iD the JSON order is preserved and it would be the first key)
			for ( NSString * key in tags ) {
				if ( [ignore containsObject:key] )
					return;
				[areaKeys setObject:[NSMutableDictionary new] forKey:key];
			}
		}];

		// blacklist
		[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * field, NSDictionary * dict, BOOL * stop) {
			if ( dict[@"suggestion"] )
				return;
			NSArray * geom = dict[ @"geometry"];
			if ( [geom containsObject:@"area"] )
				return;
			NSDictionary * tags = dict[@"tags"];
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


-(void)presetsForFeature:(NSString *)featureName geometry:(NSString *)geometry field:(NSString *)fieldType allFields:(NSMutableSet *)fieldSet update:(void (^)(void))update
{
	NSDictionary * featureDict = g_presetsDict[ featureName ];
	NSArray * fields = featureDict[fieldType];
	if ( fields == nil ) {
		// inherit from parent
		NSRange slash = [featureName rangeOfString:@"/" options:NSBackwardsSearch];
		if ( slash.length ) {
			NSString * parent = [featureName substringToIndex:slash.location];
			[self presetsForFeature:parent geometry:geometry field:fieldType allFields:fieldSet update:update];
		}
		return;
	}

	for ( NSString * field in fields ) {

		if ( [fieldSet containsObject:field] )
			continue;
		[fieldSet addObject:field];

		CommonTagGroup * group = [self groupForField:field geometry:geometry update:update];
		if ( group == nil )
			continue;
		// if both this group and the previous don't have a name then merge them
		if ( (group.name == nil || group.isDrillDown) && _sectionList.count > 1 ) {
			CommonTagGroup * prev = _sectionList.lastObject;
			if ( prev.name == nil ) {
				[prev mergeTagsFromGroup:group];
				continue;
			}
		}
		[_sectionList addObject:group];
	}
}

-(void)setPresetsForFeature:(NSString *)featureName tags:(NSDictionary *)objectTags geometry:(NSString *)geometry update:(void (^)(void))update
{
	NSDictionary * featureDict = g_presetsDict[ featureName ];

	_featureName = featureDict[ @"name" ];

	// Always start with Type and Name
	CommonTagKey * typeTag = [CommonTagKey tagWithName:@"Type" tagKey:nil defaultValue:nil placeholder:@"" keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeNone presets:@[@"",@""]];
	CommonTagKey * nameTag = [CommonTagKey tagWithName:g_fieldsDict[@"name"][@"label"] tagKey:@"name" defaultValue:nil placeholder:g_fieldsDict[@"name"][@"placeholder"] keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeWords presets:nil];
	CommonTagGroup * typeGroup = [CommonTagGroup groupWithName:@"Type" tags:@[ typeTag, nameTag ] ];
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
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:customGroup];
		[_sectionList addObject:group];
	}

	// Add presets specific to the type
	NSMutableSet * fieldSet = [NSMutableSet new];
	[self presetsForFeature:featureName geometry:geometry field:@"fields"     allFields:fieldSet update:update];
	[_sectionList addObject:[CommonTagGroup groupWithName:nil tags:nil]];	// Create a break between the common items and the rare items
	[self presetsForFeature:featureName geometry:geometry field:@"moreFields" allFields:fieldSet update:update];

#if 0 // not sure we still need these since ID presets cover most of these now
	// Add generic presets
	NSArray * extras = @[ @"elevation", @"note", @"phone", @"website", @"wheelchair", @"wikipedia" ];
	CommonTagGroup * extraGroup = [CommonTagGroup groupWithName:@"Other" tags:nil];
	for ( NSString * field in extras ) {
		if ( [fieldSet containsObject:field] )
			continue;
		CommonTagGroup * group = [self groupForField:field geometry:geometry update:update];
		[extraGroup mergeTagsFromGroup:group];
	}
	[_sectionList addObject:extraGroup];
#endif
}

-(instancetype)init
{
	self = [super init];
	if ( self ) {
	}
	return self;
}

-(NSInteger)sectionCount
{
	return _sectionList.count;
}

-(CommonTagGroup *)groupAtIndex:(NSInteger)index
{
	return _sectionList[ index ];
}

-(NSInteger)tagsInSection:(NSInteger)index
{
	CommonTagGroup * group = _sectionList[ index ];
	return group.tags.count;
}

-(CommonTagKey *)tagAtSection:(NSInteger)section row:(NSInteger)row
{
	CommonTagGroup * group = _sectionList[ section ];
	CommonTagKey * tag = group.tags[ row ];
	return tag;
}

-(CommonTagKey *)tagAtIndexPath:(NSIndexPath *)indexPath
{
#if TARGET_OS_IPHONE
	return [self tagAtSection:indexPath.section row:indexPath.row];
#else
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
	return [self tagAtSection:section row:row];
#endif
}

@end



@implementation CustomPreset
-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)key placeholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize presets:(NSArray *)presets
{
	return [super initWithName:name tagKey:key defaultValue:nil placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
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



@implementation CommonTagCategory
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
	NSDictionary * dict = g_categoriesDict[ _categoryName ];
	return dict[ @"name" ];
}
-(UIImage *)icon
{
	return nil;
}
-(NSArray *)members
{
	NSDictionary * dict = g_categoriesDict[ _categoryName ];
	NSArray * m = dict[ @"members" ];
	NSMutableArray * m2 = [NSMutableArray new];
	for ( NSString * p in m ) {
		CommonTagFeature * t = [CommonTagFeature commonTagFeatureWithName:p];
		if ( p ) {
			[m2 addObject:t];
		}
	}
	return m2;
}
@end


@implementation CommonTagFeature
@synthesize icon = _icon;

+(instancetype)commonTagFeatureWithName:(NSString *)name
{
	if ( name == nil )
		return nil;
	// all tags are single-instanced, so we can easily compare them
	if ( g_FeatureRepository == nil ) {
		g_FeatureRepository = [NSMutableDictionary new];
	}
	CommonTagFeature * tag = g_FeatureRepository[ name ];
	if ( tag == nil ) {
		tag = [[CommonTagFeature alloc] initWithName:name];
		if ( tag == nil ) {
			tag = (id)[NSNull null];
		}
		g_FeatureRepository[ name ] = tag;
	}
	return [tag isKindOfClass:[NSNull class]] ? nil : tag;
}

-(instancetype)initWithName:(NSString *)name
{
	self = [super init];
	if ( self ) {
		_featureName	= name;
		_dict			= g_presetsDict[ name ];
		if ( self.tags.count == 0 ) {
			return nil;	// placeholder (line,area,point)
		}
	}
	return self;
}

-(NSString	*)friendlyName
{
	return _dict[ @"name" ];
}

-(TagInfo *)tagInfo
{
	if ( _tagInfo == nil ) {
		[self.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
			TagInfo * info = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForKey:key value:value];
			if ( info && info.belongsTo == nil ) {
				_tagInfo = info;
				*stop = YES;
			}
		}];
	}
	return _tagInfo;
}

-(NSString *)summary
{
	TagInfo * tagInfo = [self tagInfo];
	return tagInfo.summary;
}


// Icons and names are synced to the iD presets.json file.
// SVG icons can be found in Maki/Temaki and the iD source tree
// To convert from SVG to PDF use: /Volumes/Inkscape/Inkscape.app/Contents/MacOS/inkscape  --export-type=pdf *.svg
// To rename files with the proper prefix use: for f in `ls *.pdf`; do echo mv $f `echo $f | sed 's/^/maki-/;s/-15//'`; done | bash
-(UIImage *)iconUncached
{
	NSString * iconName = _dict[ @"icon" ];
	if ( iconName ) {
		UIImage * icon = [UIImage imageNamed:iconName];
		if ( icon ) {
			return icon;
		}
	}
	return (id)[NSNull null];
}


-(UIImage *)icon
{
	extern UIImage * IconScaledForDisplay(UIImage *icon);

	if ( _icon == nil ) {
		_icon = [self iconUncached];
		if ( ![_icon isKindOfClass:[NSNull class]] ) {
			_icon = IconScaledForDisplay( _icon );
		}
	}
	if ( [_icon isKindOfClass:[NSNull class]] )
		return nil;
	return _icon;
}


-(NSArray *)terms
{
	return _dict[ @"terms" ];
}
-(NSArray *)geometry
{
	return _dict[ @"geometry" ];
}
-(NSDictionary *)tags
{
	return _dict[ @"tags" ];
}
-(NSDictionary *)addTags
{
	NSDictionary * tags = _dict[ @"addTags" ];
	if ( tags == nil )
		tags = self.tags;
	return tags;
}
-(NSDictionary *)removeTags
{
	NSDictionary * tags =  _dict[ @"removeTags" ];
	if ( tags == nil )
		tags = self.tags;
	return tags;
}
-(BOOL)suggestion
{
	return _dict[ @"suggestion" ] != nil;
}

-(NSDictionary *)defaultValuesForGeometry:(NSString *)geometry
{
	NSMutableDictionary * result = nil;
	for ( NSString * field in _dict[@"fields"]  ) {
		NSDictionary * fieldDict = g_fieldsDict[ field ];
		NSString * value = fieldDict[ @"default" ];
		if ( value == nil )
			continue;
		NSString * key = fieldDict[ @"key" ];
		if ( key == nil )
			continue;
		NSString * geom = fieldDict[@"geometry"];
		if ( geom && [geom rangeOfString:geometry].location == NSNotFound )
			continue;
		if ( result == nil )
			result = [NSMutableDictionary dictionaryWithObject:value forKey:key];
		else
			[result setObject:value forKey:key];
	}
	return result;
}

-(BOOL)matchesSearchText:(NSString *)searchText
{
	if ( [self.featureName rangeOfString:searchText options:NSCaseInsensitiveSearch].length > 0 ) {
		return YES;
	}
	if ( [self.friendlyName rangeOfString:searchText options:NSCaseInsensitiveSearch].length > 0 ) {
		return YES;
	}
	for ( NSString * term in self.terms ) {
		if ( [term rangeOfString:searchText options:NSCaseInsensitiveSearch].length > 0 ) {
			return YES;
		}
	}
	return NO;
}

@end



@implementation PresetLanguages
{
	NSMutableArray 		* _codeList;
}
-(instancetype)init
{
	self = [super init];
	if ( self ) {
		NSString * path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"presets/translations"];
		NSArray * languageFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL];
		languageFiles = [languageFiles arrayByAddingObject:@"en.json"];
		
		_codeList = [NSMutableArray new];
		for ( NSString * file in languageFiles ) {
			NSString * code = [file stringByReplacingOccurrencesOfString:@".json" withString:@""];
			[_codeList addObject:code];
		}
		
		[_codeList sortUsingComparator:^NSComparisonResult(NSString * code1, NSString * code2) {
			NSString * s1 = [self languageNameForCode:code1];
			NSString * s2 = [self languageNameForCode:code2];
			return [s1 compare:s2 options:NSCaseInsensitiveSearch];
		}];
	}
	return self;
}
-(NSString *)preferredLanguageCode
{
	NSString * code = [[NSUserDefaults standardUserDefaults] objectForKey:@"preferredLanguage"];
	if ( code == nil ) {
		NSArray * userPrefs = [NSLocale preferredLanguages];
		NSArray * matches = [NSBundle preferredLocalizationsFromArray:_codeList forPreferences:userPrefs];
		code = matches.count > 0 ? matches[0] : @"en";
	}
	return code;
}
-(void)setPreferredLanguageCode:(NSString *)code
{
	[[NSUserDefaults standardUserDefaults] setObject:code forKey:@"preferredLanguage"];
}

-(NSArray *)languageCodes
{
	return _codeList;
}
-(NSString *)languageNameForCode:(NSString *)code
{
	NSLocale * locale =  [NSLocale localeWithLocaleIdentifier:code];
	NSString * name = [locale displayNameForKey:NSLocaleIdentifier value:code];
	return name;
}
-(NSString *)localLanguageNameForCode:(NSString *)code
{
	NSString * name = [[NSLocale currentLocale] displayNameForKey:NSLocaleIdentifier value:code];
	return name;
}

// https://wiki.openstreetmap.org/wiki/Nominatim/Country_Codes
+(NSString *)languageCodesForCountryCode:(NSString *)countryCode
{
	static NSDictionary * map = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		map = @{
			@"ad" : @"ca",
			@"ae" : @"ar",
			@"af" : @"fa,ps",
			@"ag" : @"en",
			@"ai" : @"en",
			@"al" : @"sq",
			@"am" : @"hy",
			@"an" : @"nl,en",
			@"ao" : @"pt",
			// 'aq" : @"",
			@"ar" : @"es",
			@"as" : @"en,sm",
			@"at" : @"de",
			@"au" : @"en",
			@"aw" : @"nl,pap",
			@"ax" : @"sv",
			@"ba" : @"bs,hr,sr",
			@"bb" : @"en",
			@"bd" : @"bn",
			@"be" : @"nl,fr,de",
			@"bf" : @"fr",
			@"bh" : @"ar",
			@"bi" : @"fr",
			@"bj" : @"fr",
			@"bl" : @"fr",
			@"bm" : @"en",
			@"bn" : @"ms",
			@"bo" : @"es,qu,ay",
			@"br" : @"pt",
			@"bs" : @"en",
			@"bt" : @"dz",
			@"bv" : @"no",
			@"bw" : @"en,tn",
			@"by" : @"be,ru",
			@"bz" : @"en",
			@"ca" : @"en,fr",
			@"cc" : @"en",
			@"cd" : @"fr",
			@"cf" : @"fr",
			@"cg" : @"fr",
			@"ch" : @"de,fr,it,rm",
			@"ci" : @"fr",
			@"ck" : @"en,rar",
			@"cl" : @"es",
			@"cm" : @"fr,en",
			@"cn" : @"zh",
			@"co" : @"es",
			@"cr" : @"es",
			@"cu" : @"es",
			@"cv" : @"pt",
			@"cx" : @"en",
			@"cy" : @"el,tr",
			@"cz" : @"cs",
			@"de" : @"de",
			@"dj" : @"fr,ar,so",
			@"dk" : @"da",
			@"dm" : @"en",
			@"do" : @"es",
			@"dz" : @"ar",
			@"ec" : @"es",
			@"ee" : @"et",
			@"eg" : @"ar",
			@"eh" : @"ar,es,fr",
			@"er" : @"ti,ar,en",
			@"es" : @"ast,ca,es,eu,gl",
			@"et" : @"am,om",
			@"fi" : @"fi,sv,se",
			@"fj" : @"en",
			@"fk" : @"en",
			@"fm" : @"en",
			@"fo" : @"fo",
			@"fr" : @"fr",
			@"ga" : @"fr",
			@"gb" : @"en,ga,cy,gd,kw",
			@"gd" : @"en",
			@"ge" : @"ka",
			@"gf" : @"fr",
			@"gg" : @"en",
			@"gh" : @"en",
			@"gi" : @"en",
			@"gl" : @"kl,da",
			@"gm" : @"en",
			@"gn" : @"fr",
			@"gp" : @"fr",
			@"gq" : @"es,fr,pt",
			@"gr" : @"el",
			@"gs" : @"en",
			@"gt" : @"es",
			@"gu" : @"en,ch",
			@"gw" : @"pt",
			@"gy" : @"en",
			@"hk" : @"zh,en",
			@"hm" : @"en",
			@"hn" : @"es",
			@"hr" : @"hr",
			@"ht" : @"fr,ht",
			@"hu" : @"hu",
			@"id" : @"id",
			@"ie" : @"en,ga",
			@"il" : @"he",
			@"im" : @"en",
			@"in" : @"hi,en",
			@"io" : @"en",
			@"iq" : @"ar,ku",
			@"ir" : @"fa",
			@"is" : @"is",
			@"it" : @"it,de,fr",
			@"je" : @"en",
			@"jm" : @"en",
			@"jo" : @"ar",
			@"jp" : @"ja",
			@"ke" : @"sw,en",
			@"kg" : @"ky,ru",
			@"kh" : @"km",
			@"ki" : @"en",
			@"km" : @"ar,fr",
			@"kn" : @"en",
			@"kp" : @"ko",
			@"kr" : @"ko,en",
			@"kw" : @"ar",
			@"ky" : @"en",
			@"kz" : @"kk,ru",
			@"la" : @"lo",
			@"lb" : @"ar,fr",
			@"lc" : @"en",
			@"li" : @"de",
			@"lk" : @"si,ta",
			@"lr" : @"en",
			@"ls" : @"en,st",
			@"lt" : @"lt",
			@"lu" : @"lb,fr,de",
			@"lv" : @"lv",
			@"ly" : @"ar",
			@"ma" : @"ar",
			@"mc" : @"fr",
			@"md" : @"ru,uk,ro",
			@"me" : @"srp,sq,bs,hr,sr",
			@"mf" : @"fr",
			@"mg" : @"mg,fr",
			@"mh" : @"en,mh",
			@"mk" : @"mk",
			@"ml" : @"fr",
			@"mm" : @"my",
			@"mn" : @"mn",
			@"mo" : @"zh,pt",
			@"mp" : @"ch",
			@"mq" : @"fr",
			@"mr" : @"ar,fr",
			@"ms" : @"en",
			@"mt" : @"mt,en",
			@"mu" : @"mfe,fr,en",
			@"mv" : @"dv",
			@"mw" : @"en,ny",
			@"mx" : @"es",
			@"my" : @"ms",
			@"mz" : @"pt",
			@"na" : @"en,sf,de",
			@"nc" : @"fr",
			@"ne" : @"fr",
			@"nf" : @"en,pih",
			@"ng" : @"en",
			@"ni" : @"es",
			@"nl" : @"nl",
			@"no" : @"nb,nn,no,se",
			@"np" : @"ne",
			@"nr" : @"na,en",
			@"nu" : @"niu,en",
			@"nz" : @"mi,en",
			@"om" : @"ar",
			@"pa" : @"es",
			@"pe" : @"es",
			@"pf" : @"fr",
			@"pg" : @"en,tpi,ho",
			@"ph" : @"en,tl",
			@"pk" : @"en,ur",
			@"pl" : @"pl",
			@"pm" : @"fr",
			@"pn" : @"en,pih",
			@"pr" : @"es,en",
			@"ps" : @"ar,he",
			@"pt" : @"pt",
			@"pw" : @"en,pau,ja,sov,tox",
			@"py" : @"es,gn",
			@"qa" : @"ar",
			@"re" : @"fr",
			@"ro" : @"ro",
			@"rs" : @"sr",
			@"ru" : @"ru",
			@"rw" : @"rw,fr,en",
			@"sa" : @"ar",
			@"sb" : @"en",
			@"sc" : @"fr,en,crs",
			@"sd" : @"ar,en",
			@"se" : @"sv",
			@"sg" : @"en,ms,zh,ta",
			@"sh" : @"en",
			@"si" : @"sl",
			@"sj" : @"no",
			@"sk" : @"sk",
			@"sl" : @"en",
			@"sm" : @"it",
			@"sn" : @"fr",
			@"so" : @"so,ar",
			@"sr" : @"nl",
			@"st" : @"pt",
			@"ss" : @"en",
			@"sv" : @"es",
			@"sy" : @"ar",
			@"sz" : @"en,ss",
			@"tc" : @"en",
			@"td" : @"fr,ar",
			@"tf" : @"fr",
			@"tg" : @"fr",
			@"th" : @"th",
			@"tj" : @"tg,ru",
			@"tk" : @"tkl,en,sm",
			@"tl" : @"pt,tet",
			@"tm" : @"tk",
			@"tn" : @"ar",
			@"to" : @"en",
			@"tr" : @"tr",
			@"tt" : @"en",
			@"tv" : @"en",
			@"tw" : @"zh",
			@"tz" : @"sw,en",
			@"ua" : @"uk",
			@"ug" : @"en,sw",
			@"um" : @"en",
			@"us" : @"en",
			@"uy" : @"es",
			@"uz" : @"uz,kaa",
			@"va" : @"it",
			@"vc" : @"en",
			@"ve" : @"es",
			@"vg" : @"en",
			@"vi" : @"en",
			@"vn" : @"vi",
			@"vu" : @"bi,en,fr",
			@"wf" : @"fr",
			@"ws" : @"sm,en",
			@"ye" : @"ar",
			@"yt" : @"fr",
			@"za" : @"zu,xh,af,st,tn,en",
			@"zm" : @"en",
			@"zw" : @"en,sn,nd ",
		};
	});
	return map[ countryCode ];
}


@end

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

#define USE_SUGGESTIONS	1

#if !TARGET_OS_IPHONE
const int UIKeyboardTypeDefault					= 0;
const int UIKeyboardTypeNumbersAndPunctuation 	= 1;
const int UIKeyboardTypeURL						= 2;

const int UITextAutocapitalizationTypeNone		= 0;
const int UITextAutocapitalizationTypeSentences = 1;
const int UITextAutocapitalizationTypeWords		= 2;
#endif

static NSDictionary<NSString *,NSDictionary *> 				* g_jsonAddressFormatsDict;	// address formats for different countries
static NSDictionary<NSString *,NSArray *> 					* g_jsonDefaultsDict;		// map a geometry to a set of features/categories
static NSDictionary<NSString *,NSDictionary *> 				* g_jsonCategoriesDict;		// map a top-level category ("building") to a set of specific features ("building/retail")
static NSDictionary<NSString *,NSDictionary *> 				* g_jsonPresetsDict;		// tags for a specific feature
static NSDictionary<NSString *,NSDictionary *> 				* g_jsonFieldsDict;			// possible values for a preset key ("oneway=")
static NSDictionary<NSString *,NSDictionary *> 				* g_jsonTranslationDict;	// translations of all preset text

static NSMutableDictionary<NSString *,NSMutableArray *> 	* g_taginfoCache;			// OSM TagInfo database in the cloud: contains either a group or an array of values


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
	if ( g_jsonPresetsDict == nil ) {
		g_jsonAddressFormatsDict = DictionaryForFile(@"address_formats.json");
		g_jsonDefaultsDict		 = DictionaryForFile(@"preset_defaults.json");
		g_jsonCategoriesDict	 = DictionaryForFile(@"preset_categories.json");
		g_jsonPresetsDict		 = DictionaryForFile(@"presets.json");
		g_jsonFieldsDict		 = DictionaryForFile(@"fields.json");

		PresetLanguages * presetLanguages = [PresetLanguages new];	// don't need to save this, it doesn't get used again unless user changes the language
		NSString * code = presetLanguages.preferredLanguageCode;
		NSString * code2 = [code stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
		NSString * file = [NSString stringWithFormat:@"translations/%@.json",code];
		g_jsonTranslationDict	= DictionaryForFile(file);
		g_jsonTranslationDict	= g_jsonTranslationDict[ code2 ][ @"presets" ];

#ifndef __clang_analyzer__	// this confuses the analyzer because it doesn't know that top-level return values are always NSDictionary
		g_jsonDefaultsDict		= Translate( g_jsonDefaultsDict,	g_jsonTranslationDict[@"defaults"] );
		g_jsonCategoriesDict	= Translate( g_jsonCategoriesDict,	g_jsonTranslationDict[@"categories"] );
		g_jsonPresetsDict		= Translate( g_jsonPresetsDict,		g_jsonTranslationDict[@"presets"] );
		g_jsonFieldsDict		= Translate( g_jsonFieldsDict,		g_jsonTranslationDict[@"fields"] );
#endif
	}
}

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



@implementation PresetsDatabase

+(void)initialize
{
	g_jsonPresetsDict		= nil;
	g_taginfoCache		= nil;
	InitializeDictionaries();
}

+(instancetype)sharedList
{
	static dispatch_once_t onceToken;
	static PresetsDatabase * list = nil;
	dispatch_once(&onceToken, ^{
		InitializeDictionaries();
		list = [PresetsDatabase new];
	});
	return list;
}

+(NSSet *)allTagValuesForKey:(NSString *)key
{
	NSMutableSet * set = [NSMutableSet new];
	[g_jsonFieldsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
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
	[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
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
	[g_jsonFieldsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSString * key = dict[ @"key" ];
		if ( key ) {
			[set addObject:key];
		}
		NSDictionary * keys = dict[ @"keys" ];
		for ( key in keys ) {
			[set addObject:key];
		}
	}];
	[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
		NSDictionary * dict2 = dict[ @"tags" ];
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
		[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSDictionary * dict, BOOL * _Nonnull stop) {
			NSRange slash = [key rangeOfString:@"/"];
			NSString * feature = slash.location != NSNotFound ? [key substringToIndex:slash.location] : key;
			[set addObject:feature];
		}];
	});
	return set;
}


+(NSArray<PresetFeature *> *)featuresAndCategoriesForMemberList:(NSArray *)memberList
{
	NSMutableArray * list = [NSMutableArray new];
	for ( NSString * featureName in memberList ) {

		if ( [featureName hasPrefix:@"category-"] ) {

			PresetCategory * category = [[PresetCategory alloc] initWithCategoryName:featureName];
			[list addObject:category];

		} else {

			PresetFeature * tag = [PresetFeature presetFeatureForFeatureName:featureName];
			if ( tag == nil )
				continue;
			[list addObject:tag];

		}
	}
	return list;
}

+(NSArray<PresetFeature *> *)featuresAndCategoriesForGeometry:(NSString *)geometry
{
	NSArray * list = g_jsonDefaultsDict[geometry];
	NSArray * featureList = [self featuresAndCategoriesForMemberList:list];
	return featureList;
}

+(NSArray<PresetFeature *> *)featuresInCategory:(PresetCategory *)category matching:(NSString *)searchText
{
	NSMutableArray<PresetFeature *> * list = [NSMutableArray new];
	if ( category ) {
		for ( PresetFeature * tag in category.members ) {
			if ( [tag matchesSearchText:searchText] ) {
				[list addObject:tag];
			}
		}
	} else {
		NSString * countryCode = AppDelegate.shared.mapView.countryCodeForLocation;
		[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * featureName, NSDictionary * dict, BOOL *stop) {
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
				PresetFeature * tag = [PresetFeature presetFeatureForFeatureName:featureName];
				if ( tag ) {
					[list addObject:tag];
				}
			}
		}];
	}
	// sort so that regular items come before suggestions
	[list sortUsingComparator:^NSComparisonResult(PresetFeature * obj1, PresetFeature * obj2) {
		NSString * name1 = obj1.friendlyName;
		NSString * name2 = obj2.friendlyName;
#if USE_SUGGESTIONS
		int diff = obj1.suggestion - obj2.suggestion;
		if ( diff )
			return diff;
#endif
		// prefer exact matches of primary name over alternate terms
		BOOL p1 = [name1 hasPrefix:searchText];
		BOOL p2 = [name2 hasPrefix:searchText];
		if ( p1 != p2 )
			return p2 - p1;
 		return [name1 compare:name2];
	}];
	return list;
}

+(NSString *)yesForLocale
{
	NSDictionary * dict = g_jsonTranslationDict[@"fields"][@"internet_access"][@"options"];
	NSString * text = dict[ @"yes" ];
	if ( text == nil )
		text = @"Yes";
	return text;
}
+(NSString *)noForLocale
{
	NSDictionary * dict = g_jsonTranslationDict[@"fields"][@"internet_access"][@"options"];
	NSString * text = dict[ @"no" ];
	if ( text == nil )
		text = @"No";
	return text;
}

+(PresetGroup *)groupForField:(NSString *)fieldName geometry:(NSString *)geometry update:(void (^)(void))update
{
	if ( g_taginfoCache == nil ) {
		g_taginfoCache = [NSMutableDictionary new];
	}

	NSDictionary * dict = g_jsonFieldsDict[ fieldName ];
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

		NSArray * presets = @[ [PresetValue presetValueWithName:[PresetsDatabase yesForLocale] details:nil tagValue:@"yes"],
							   [PresetValue presetValueWithName:[PresetsDatabase noForLocale]  details:nil tagValue:@"no"] ];
		PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
		PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"radio"] || [type isEqualToString:@"structureRadio"] ) {

		if ( keysArray ) {

			// a list of booleans
			NSMutableArray * tags = [NSMutableArray new];
			NSArray * presets = @[ [PresetValue presetValueWithName:[PresetsDatabase yesForLocale] details:nil tagValue:@"yes"],
								   [PresetValue presetValueWithName:[PresetsDatabase noForLocale]  details:nil tagValue:@"no"] ];
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
			NSArray * presets = @[ [PresetValue presetValueWithName:[PresetsDatabase yesForLocale] details:nil tagValue:@"yes"],
								   [PresetValue presetValueWithName:[PresetsDatabase noForLocale]  details:nil tagValue:@"no"] ];
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

	} else if ( [type isEqualToString:@"combo"] || [type isEqualToString:@"semiCombo"] || [type isEqualToString:@"multiCombo"] ) {	// semiCombo is for setting semicolor delimited lists of values, which we don't support

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
							NSArray * yesNo = @[ [PresetValue presetValueWithName:[PresetsDatabase yesForLocale] details:nil tagValue:@"yes"],
											     [PresetValue presetValueWithName:[PresetsDatabase noForLocale]  details:nil tagValue:@"no"] ];
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
		for ( NSDictionary * localeDict in g_jsonAddressFormatsDict ) {
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
		PresetKey * tag = [PresetKey presetKeyWithName:label featureKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		PresetGroup * group = [PresetGroup presetGroupWithName:nil tags:@[tag]];
		return group;

	}
}

+(NSString *)featureNameForObjectDict:(NSDictionary *)objectTags geometry:(NSString *)geometry
{
	NSString * featureName = [PresetsDatabase featureNameForObjectDictSwift:g_jsonPresetsDict
																countryCode:AppDelegate.shared.mapView.countryCodeForLocation
																 objectTags:objectTags
																   geometry:geometry];
	return featureName;
}

+(NSString *)featureNameForObjectDictObjc:(NSDictionary *)objectTags geometry:(NSString *)geometry
 {
	__block double bestMatchScore = 0.0;
	__block NSString * bestMatchName = nil;

	NSString * currentCountryCode = AppDelegate.shared.mapView.countryCodeForLocation;

	[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * featureName, NSDictionary * dict, BOOL * stop) {

		if ( [featureName containsString:@"Rosa"] ) {
			NSLog(@"");
		}
		__block double totalScore = 0;
#if USE_SUGGESTIONS
		NSArray<NSString *> * countryList = dict[@"countryCodes"];
		if ( countryList.count > 0 ) {
			BOOL found = NO;
			for ( NSString * country in countryList ) {
				if ( [currentCountryCode isEqualToString:country] ) {
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
			} else if ( [key isEqualToString:@"area"] && [value isEqualToString:@"yes"] && [geometry isEqualToString:@"area"] ) {
				totalScore += 0.1;
				return;
			}
			totalScore = -1;
			*stop2 = YES;
		}];
		if ( totalScore < 0 )
			return;

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
		[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * field, NSDictionary * dict, BOOL * stop) {
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
		[g_jsonPresetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * field, NSDictionary * dict, BOOL * stop) {
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
	NSDictionary * dict = g_jsonCategoriesDict[ _categoryName ];
	return dict[ @"name" ];
}
-(UIImage *)icon
{
	return nil;
}
-(NSArray<PresetFeature *> *)members
{
	NSDictionary * dict = g_jsonCategoriesDict[ _categoryName ];
	NSArray<PresetFeature *> * m = dict[ @"members" ];
	NSMutableArray<PresetFeature *> * m2 = [NSMutableArray new];
	for ( NSString * p in m ) {
		PresetFeature * t = [PresetFeature presetFeatureForFeatureName:p];
		if ( p ) {
			[m2 addObject:t];
		}
	}
	return m2;
}
@end



@implementation PresetsForFeature

+(instancetype)presetsForFeature:(NSString *)featureName objectTags:(NSDictionary *)objectTags geometry:(NSString *)geometry  update:(void (^)(void))update
{
	PresetsForFeature * presentation = [PresetsForFeature new];
	[presentation setFeature:featureName
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

-(void)addPresetsForFieldsInFeature:(NSString *)featureName geometry:(NSString *)geometry field:(NSString *)fieldType dupSet:(NSMutableSet *)dupSet update:(void (^)(void))update
{
	NSArray * fields = nil;
	while ( (fields = g_jsonPresetsDict[ featureName ][ fieldType ]) == nil ) {
		// check parent
		NSRange slash = [featureName rangeOfString:@"/" options:NSBackwardsSearch];
		if ( slash.length == 0  ||  slash.location == 0 )
			break;
		featureName = [featureName substringToIndex:slash.location];
	}

	for ( NSString * field in fields ) {

		if ( [field hasPrefix:@"{"] && [field hasSuffix:@"}"]) {
			// copy fields from referenced item
			NSString * ref = [field substringWithRange:NSMakeRange(1, field.length-2)];
			[self addPresetsForFieldsInFeature:ref geometry:geometry field:fieldType dupSet:dupSet update:update];
			continue;
		}

		if ( [dupSet containsObject:field] )
			continue;
		[dupSet addObject:field];

		PresetGroup * group = [PresetsDatabase groupForField:field geometry:geometry update:update];
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

-(void)setFeature:(NSString *)featureName objectTags:(NSDictionary *)objectTags geometry:(NSString *)geometry update:(void (^)(void))update
{
	NSDictionary * featureDict = g_jsonPresetsDict[ featureName ];

	_featureName = featureDict[ @"name" ];

	// Always start with Type and Name
	PresetKey * typeTag = [PresetKey presetKeyWithName:@"Type" featureKey:nil defaultValue:nil placeholder:@"" keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeNone presets:@[@"",@""]];
	PresetKey * nameTag = [PresetKey presetKeyWithName:g_jsonFieldsDict[@"name"][@"label"] featureKey:@"name" defaultValue:nil placeholder:g_jsonFieldsDict[@"name"][@"placeholder"] keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeWords presets:nil];
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
	[self addPresetsForFieldsInFeature:featureName geometry:geometry field:@"fields"     dupSet:dupSet update:update];
	[_sectionList addObject:[PresetGroup presetGroupWithName:nil tags:nil]];	// Create a break between the common items and the rare items
	[self addPresetsForFieldsInFeature:featureName geometry:geometry field:@"moreFields" dupSet:dupSet update:update];
}
@end



@implementation PresetFeature
@synthesize imageScaled24 = _imageScaled24;
@synthesize imageUnscaled = _imageUnscaled;

-(instancetype)initWithName:(NSString *)featureName presets:(NSDictionary *)dict
{
	self = [super init];
	if ( self ) {
		_featureName	= featureName;
		_dict			= dict;
	}
	return self;
}

+(instancetype)presetFeatureForFeatureName:(NSString *)name
{
	NSDictionary * dict = name.length ? g_jsonPresetsDict[ name ] : nil;
	if ( dict.count == 0 )
		return nil;
	return [[PresetFeature alloc] initWithName:name presets:dict];
}

-(NSString *)description
{
	return self.friendlyName;
}

-(NSString	*)friendlyName
{
	return _dict[ @"name" ];
}

-(NSString *)summary
{
	NSString * feature = _featureName;
	for (;;) {
		NSRange slash = [feature rangeOfString:@"/" options:NSBackwardsSearch];
		if ( slash.length == 0 )
			break;
		feature = [feature substringToIndex:slash.location];
		NSDictionary * p = g_jsonPresetsDict[feature];
		NSString * s = p[@"name"];
		if ( s )
			return s;
	}

	return nil;
}


// Icons and names are synced to the iD presets.json file.
// SVG icons can be found in Maki/Temaki and the iD source tree
// To convert from SVG to PDF use: /Volumes/Inkscape/Inkscape.app/Contents/MacOS/inkscape  --export-type=pdf *.svg
// To rename files with the proper prefix use: for f in `ls *.pdf`; do echo mv $f `echo $f | sed 's/^/maki-/;s/-15//'`; done | bash
-(UIImage *)imageUnscaled
{
	if ( _imageUnscaled ) {
		return [_imageUnscaled isKindOfClass:[NSNull class]] ? nil : _imageUnscaled;
	}
	NSString * iconName = _dict[ @"icon" ];
	if ( iconName ) {
		_imageUnscaled = [UIImage imageNamed:iconName];
		if ( _imageUnscaled ) {
			return _imageUnscaled;
		}
	}
	_imageUnscaled = (id)[NSNull null];
	return nil;
}

-(UIImage *)imageScaled24
{
	extern UIImage * IconScaledForDisplay(UIImage *icon);

	if ( _imageScaled24 == nil ) {
		_imageScaled24 = self.imageUnscaled;
		if ( _imageScaled24 ) {
			_imageScaled24 = IconScaledForDisplay( _imageScaled24 );
		} else {
			_imageScaled24 = (id)[NSNull null];
		}
	}
	return [_imageScaled24 isKindOfClass:[NSNull class]] ? nil : _imageScaled24;
}

-(NSString *)logoURL
{
	return _dict[@"imageURL"];
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
		tags = self.addTags;
	return tags;
}
-(BOOL)suggestion
{
	return _dict[ @"suggestion" ] != nil;
}

-(NSArray *)inheritableField:(NSString *)field
{
	id result = _dict[ field ];
	if ( result == nil ) {
		// inherit from parent
		NSRange slash = [self.featureName rangeOfString:@"/" options:NSBackwardsSearch];
		if ( slash.length ) {
			NSString * parentName = [self.featureName substringToIndex:slash.location];
			PresetFeature * parent = [PresetFeature presetFeatureForFeatureName:parentName];
			return [parent inheritableField:field];
		}
	}
	return result;
}

-(NSArray *)fields
{
	return [self inheritableField:@"fields"];
}

-(NSArray *)moreFields
{
	return [self inheritableField:@"moreFields"];
}

-(NSDictionary *)defaultValuesForGeometry:(NSString *)geometry
{
	NSMutableDictionary * result = nil;
	for ( NSString * field in self.fields ) {
		NSDictionary * fieldDict = g_jsonFieldsDict[ field ];
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
-(BOOL)preferredLanguageIsDefault
{
	NSString * code = [[NSUserDefaults standardUserDefaults] objectForKey:@"preferredLanguage"];
	return code == nil;
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

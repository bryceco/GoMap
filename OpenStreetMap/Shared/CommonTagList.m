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

static NSDictionary * g_defaultsDict;
static NSDictionary * g_categoriesDict;
static NSDictionary * g_presetsDict;
static NSDictionary * g_fieldsDict;
static NSDictionary * g_translationDict;

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
		g_defaultsDict		= DictionaryForFile(@"defaults.json");
		g_categoriesDict	= DictionaryForFile(@"categories.json");
		g_presetsDict		= DictionaryForFile(@"presets.json");
		g_fieldsDict		= DictionaryForFile(@"fields.json");

		NSLocale * currentLocale = [NSLocale autoupdatingCurrentLocale];
		NSString * ident = currentLocale.localeIdentifier;
//		ident = @"zh_TW";
		NSString * file = [NSString stringWithFormat:@"presets_%@.json",ident];
		g_translationDict	= DictionaryForFile(file);

		g_defaultsDict		= Translate( g_defaultsDict,	g_translationDict[ident][@"presets"][@"defaults"] );
		g_categoriesDict	= Translate( g_categoriesDict,	g_translationDict[ident][@"presets"][@"categories"] );
		g_presetsDict		= Translate( g_presetsDict,		g_translationDict[ident][@"presets"][@"presets"] );
		g_fieldsDict		= Translate( g_fieldsDict,		g_translationDict[ident][@"presets"][@"fields"] );
	}
}

static NSString * PrettyTag( NSString * tag )
{
	tag = [tag stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	tag = [tag capitalizedString];
	return tag;
}



@implementation CommonTagValue
-(instancetype)initWithName:(NSString *)name tagValue:(NSString *)value
{
	self = [super init];
	if ( self ) {
		_name = name ?: PrettyTag(value);
		_tagValue = value;
	}
	return self;
}
+(instancetype)presetWithName:(NSString *)name tagValue:(NSString *)value
{
	return [[CommonTagValue alloc] initWithName:name tagValue:value];
}
-(void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_name forKey:@"name"];
	[coder encodeObject:_tagValue forKey:@"tagValue"];
}

-(instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_name = [coder decodeObjectForKey:@"name"];
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
		if ( tags.count )	assert( [tags.lastObject isKindOfClass:[CommonTagKey class]] );
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
		[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * featureName, NSDictionary * dict, BOOL *stop) {
			if ( dict[@"suggestion"] )
				return;
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


-(NSString *)featureName
{
	return _featureName;
}

-(CommonTagGroup *)groupForField:(NSString *)fieldName geometry:(NSString *)geometry update:(void (^)(void))update
{
	static NSMutableDictionary * taginfoCache = nil;
	if ( taginfoCache == nil ) {
		taginfoCache = [NSMutableDictionary new];
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
	NSArray		*	keyArray			= dict[ @"keys" ];
	NSString	*	givenName			= dict[ @"label" ];
	NSString	*	placeholder			= dict[ @"placeholder" ];
	NSDictionary *	optionStringsDict	= dict[ @"strings" ][ @"options" ];
	NSArray		*	optionArray			= dict[ @"options" ];
	NSString	*	defaultValue		= dict[ @"default" ];
	UIKeyboardType					keyboard = UIKeyboardTypeDefault;
	UITextAutocapitalizationType	capitalize = [key hasPrefix:@"name:"] ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeNone;


//r	DLog(@"%@",dict);

	if ( [type isEqualToString:@"defaultcheck"] || [type isEqualToString:@"check"] ) {

		NSArray * presets = @[ [CommonTagValue presetWithName:@"Yes" tagValue:@"yes"], [CommonTagValue presetWithName:@"No" tagValue:@"no"] ];
		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"radio"] ) {

		NSMutableArray * presets = [NSMutableArray new];
		if ( keyArray ) {
			for ( NSString * k in keyArray ) {
				NSString * label = optionStringsDict[ k ];
				[presets addObject:[CommonTagValue presetWithName:label tagValue:k]];
			}
		} else if ( optionArray ) {
			for ( NSString * v in optionArray ) {
				[presets addObject:[CommonTagValue presetWithName:nil tagValue:v]];
			}
		} else {
#if DEBUG
			assert(NO);
#endif
		}

		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"combo"] ) {

		NSMutableArray * presets = [NSMutableArray new];
		if ( optionStringsDict ) {

			[optionStringsDict enumerateKeysAndObjectsUsingBlock:^(NSString * k, NSString * v, BOOL *stop) {
				[presets addObject:[CommonTagValue presetWithName:v tagValue:k]];
			}];
			[presets sortUsingComparator:^NSComparisonResult(CommonTagValue * obj1, CommonTagValue * obj2) {
				return [obj1.name compare:obj2.name];
			}];

		} else if ( optionArray ) {

			for ( NSString * v in optionArray ) {
				[presets addObject:[CommonTagValue presetWithName:nil tagValue:v]];
			}

		} else {

			// check tagInfo
			if ( taginfoCache[fieldName] ) {
				// already got them once
				presets = taginfoCache[fieldName];
			} else if ( update ) {
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
					NSString * urlText = [NSString stringWithFormat:@"http://taginfo.openstreetmap.org/api/4/key/values?key=%@&page=1&rp=25&sortname=count_all&sortorder=desc",key];
					NSURL * url = [NSURL URLWithString:urlText];
					NSData * data = [NSData dataWithContentsOfURL:url];
					if ( data ) {
						NSMutableArray * presets2 = [NSMutableArray new];
						NSDictionary * dict2 = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
						NSArray * values = dict2[@"data"];
						for ( NSDictionary * v in values ) {
							if ( [v[@"fraction"] doubleValue] < 0.01 )
								continue;
							NSString * val = v[@"value"];
							[presets2 addObject:[CommonTagValue presetWithName:nil tagValue:val]];
						}
						dispatch_async(dispatch_get_main_queue(), ^{
							[taginfoCache setObject:presets2 forKey:fieldName];
							update();
						});
					}
				});
			} else {
				// already submitted to network, so don't do it again
			}
		}

		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[ tag ]];
		return group;

	} else if ( [type isEqualToString:@"address"] ) {

		NSString * ref = dict[@"reference"][@"key"];
		NSDictionary * placeholders = dict[ @"strings" ][ @"placeholders" ];
		NSMutableArray * addrs = [NSMutableArray new];
		for ( NSString * k in dict[@"keys"] ) {
			NSString * name = [k substringFromIndex:ref.length+1];
			placeholder = placeholders[name];
			name = PrettyTag( name );
			keyboard = [k isEqualToString:@"addr:housenumber"] || [k isEqualToString:@"addr:postcode"] ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault;
			CommonTagKey * tag = [CommonTagKey tagWithName:name tagKey:k defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeWords presets:nil];
			[addrs addObject:tag];
		}
		CommonTagGroup * group = [CommonTagGroup groupWithName:givenName tags:addrs];
		return group;

	} else if ( [type isEqualToString:@"text"] ||
			    [type isEqualToString:@"number"] ||
			    [type isEqualToString:@"textarea"] ||
			    [type isEqualToString:@"tel"] ||
			    [type isEqualToString:@"url"] ||
			    [type isEqualToString:@"wikipedia"] )
	{

		// no presets
		if ( [type isEqualToString:@"number"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypeDecimalPad doesn't have Done button
		else if ( [type isEqualToString:@"tel"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypePhonePad doesn't have Done Button
		else if ( [type isEqualToString:@"url"] || [type isEqualToString:@"wikipedia"] )
			keyboard = UIKeyboardTypeURL;
		else if ( [type isEqualToString:@"textarea"] )
			capitalize = UITextAutocapitalizationTypeSentences;
		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"maxspeed"] ) {

		// special case
		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"access"] ) {

		// special case
		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"typeCombo"] ) {

		// skip since this is for selecting generic objects
		return nil;

	} else {

#if DEBUG
		assert(NO);
#endif
		CommonTagKey * tag = [CommonTagKey tagWithName:givenName tagKey:key defaultValue:defaultValue placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonTagGroup * group = [CommonTagGroup groupWithName:nil tags:@[tag]];
		return group;

	}
}

+(NSString *)featureNameForObjectDict:(NSDictionary *)objectTags geometry:(NSString *)geometry
{
	__block double bestMatchScore = 0.0;
	__block NSString * bestMatchName = nil;

	[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * featureName, NSDictionary * dict, BOOL * stop) {

		__block double totalScore = 0;
		id suggestion = dict[@"suggestion"];
		if ( suggestion )
			return;

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

		[keyvals enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop2) {
			NSString * v = objectTags[ key ];
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
		if ( totalScore > bestMatchScore ) {
			bestMatchName = featureName;
			bestMatchScore = totalScore;
		}
	}];
	return bestMatchName;
}

-(void)setPresetsForDict:(NSDictionary *)objectTags geometry:(NSString *)geometry update:(void (^)(void))update
{
	NSString * featureName = [CommonTagList featureNameForObjectDict:objectTags geometry:geometry];
	NSDictionary * featureDict = g_presetsDict[ featureName ];

	_featureName = featureDict[ @"name" ];

	// Always start with Type and Name
	CommonTagKey * typeTag = [CommonTagKey tagWithName:@"Type" tagKey:nil defaultValue:nil placeholder:@"" keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeNone presets:@[@"",@""]];
	CommonTagKey * nameTag = [CommonTagKey tagWithName:@"Name" tagKey:@"name" defaultValue:nil placeholder:@"common name" keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeWords presets:nil];
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
	for ( NSString * field in featureDict[@"fields"] ) {

		if ( [fieldSet containsObject:field] )
			continue;
		[fieldSet addObject:field];

		CommonTagGroup * group = [self groupForField:field geometry:geometry update:update];
		if ( group == nil )
			continue;
		// if both this group and the previous don't have a name then merge them
		if ( group.name == nil && _sectionList.count > 1 ) {
			CommonTagGroup * prev = _sectionList.lastObject;
			if ( prev.name == nil ) {
				[prev mergeTagsFromGroup:group];
				continue;
			}
		}
		[_sectionList addObject:group];
	}

	// Add generic presets
	NSArray * extras = @[ @"elevation", @"note", @"phone", @"website", @"wheelchair", @"wikipedia" ];
	CommonTagGroup * extraGroup = [CommonTagGroup groupWithName:@"Other" tags:nil];
	for ( NSString * field in extras ) {
		CommonTagGroup * group = [self groupForField:field geometry:geometry update:update];
		[extraGroup mergeTagsFromGroup:group];
	}
	[_sectionList addObject:extraGroup];
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
	return [self tagAtSection:indexPath.section row:indexPath.row];
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
	NSString * path = [CustomPresetList archivePath];
	_list = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
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
	static NSMutableDictionary * g_FeatureRepository = nil;
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
-(UIImage *)icon
{
	TagInfo * tagInfo = [self tagInfo];
	_icon = tagInfo.icon;
	if ( _icon == nil ) {
		NSString * iconName = _dict[ @"icon" ];
		if ( iconName ) {
			NSString * path = [NSString stringWithFormat:@"poi/%@-24", iconName];
			_icon = [UIImage imageNamed:path];
		}
	}
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

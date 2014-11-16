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

-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder
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
		_keyboardType	= keyboard;
		_autocapitalizationType = capitalize;
		_presetList		= presets.count ? presets : nil;
	}
	return self;
}
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder
				  keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
				   presets:(NSArray *)presets
{
	return [[CommonTag alloc] initWithName:name tagKey:tag placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
}
@end


@implementation CommonTagList

+(instancetype)sharedList
{
	static dispatch_once_t onceToken;
	static CommonTagList * list = nil;
	dispatch_once(&onceToken, ^{
		[CommonTagList initializeDictionaries];
		list = [CommonTagList new];
	});
	return list;
}

+(NSDictionary *)dictionaryForFileFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)
{
	va_list args;
	va_start(args, format);
	NSString * fileName = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	NSString * rootDir = [[NSBundle mainBundle] resourcePath];
	NSString * rootPresetPath = [NSString stringWithFormat:@"%@/presets/%@",rootDir,fileName];
	NSData * rootPresetData = [NSData dataWithContentsOfFile:rootPresetPath];
	NSDictionary * dict = [NSJSONSerialization JSONObjectWithData:rootPresetData options:0 error:NULL];
	DbgAssert(dict);
	return dict;
}

+(void)initializeDictionaries
{
	if ( g_presetsDict == nil ) {
		g_presetsDict		= [CommonTagList dictionaryForFileFormat:@"presets.json"];;
		g_defaultsDict		= [CommonTagList dictionaryForFileFormat:@"defaults.json"];
		g_categoriesDict	= [CommonTagList dictionaryForFileFormat:@"categories.json"];
		g_fieldsDict		= [CommonTagList dictionaryForFileFormat:@"presets.json"];;
	}
}

-(NSString *)featureName
{
	return _featureName;
}

-(CommonGroup *)groupForField:(NSString *)fieldName geometry:(NSString *)geometry update:(void (^)(void))update
{
	static NSMutableDictionary * taginfoCache = nil;
	static NSMutableDictionary * fieldsCache = nil;
	if ( taginfoCache == nil ) {
		taginfoCache = [NSMutableDictionary new];
		fieldsCache = [NSMutableDictionary new];
	}

	NSDictionary * dict = fieldsCache[ fieldName ];
	if ( dict == nil ) {
		dict = [CommonTagList dictionaryForFileFormat:@"fields/%@.json",fieldName];
		if ( dict == nil )
			dict = [NSDictionary new];
		fieldsCache[ fieldName ] = dict;
	}
	if ( dict.count == 0 )
		return nil;

	NSString * geo = dict[@"geometry"];
	if ( [geo rangeOfString:geometry].location == NSNotFound ) {
		return nil;
	}

	NSString	*	key = dict[@"key"] ?: fieldName;
	NSString	*	type = dict[@"type"];
	NSArray		*	keyArray = dict[ @"keys" ];
	NSString	*	givenName = dict[@"label"];
	NSString	*	placeholder = dict[@"placeholder"];
	NSDictionary *	optionStringsDict = dict[ @"strings" ][ @"options" ];
	NSArray		*	optionArray = dict[ @"options" ];
	UIKeyboardType					keyboard = UIKeyboardTypeDefault;
	UITextAutocapitalizationType	capitalize = UITextAutocapitalizationTypeNone;


//r	DLog(@"%@",dict);

	if ( [type isEqualToString:@"defaultcheck"] || [type isEqualToString:@"check"] ) {

		NSArray * presets = @[ [CommonPreset presetWithName:@"Yes" tagValue:@"yes"], [CommonPreset presetWithName:@"No" tagValue:@"no"] ];
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
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

		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
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
							[presets2 addObject:[CommonPreset presetWithName:nil tagValue:val]];
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

		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeNone presets:presets];
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
			CommonTag * tag = [CommonTag tagWithName:name tagKey:k placeholder:placeholder keyboard:keyboard capitalize:UITextAutocapitalizationTypeWords presets:nil];
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
		if ( [type isEqualToString:@"number"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypeDecimalPad doesn't have Done button
		else if ( [type isEqualToString:@"tel"] )
			keyboard = UIKeyboardTypeNumbersAndPunctuation; // UIKeyboardTypePhonePad doesn't have Done Button
		else if ( [type isEqualToString:@"url"] || [type isEqualToString:@"wikipedia"] )
			keyboard = UIKeyboardTypeURL;
		else if ( [type isEqualToString:@"textarea"] )
			capitalize = UITextAutocapitalizationTypeSentences;
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"maxspeed"] ) {

		// special case
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"access"] ) {

		// special case
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	} else if ( [type isEqualToString:@"typeCombo"] ) {

		// skip since this is for selecting generic objects
		return nil;

	} else {

#if DEBUG
		assert(NO);
#endif
		CommonTag * tag = [CommonTag tagWithName:givenName tagKey:key placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:nil];
		CommonGroup * group = [CommonGroup groupWithName:nil tags:@[tag]];
		return group;

	}
}

-(void)setPresetsForDict:(NSDictionary *)tagDict geometry:(NSString *)geometry update:(void (^)(void))update
{
	__block double bestMatchScore = 0.0;
	__block NSDictionary * bestMatchDict = nil;

	[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * fieldName, NSDictionary * dict, BOOL * stop) {

		__block BOOL match = NO;
		id suggestion = dict[@"suggestion"];
		if ( suggestion )
			return;

		NSArray * geom = dict[@"geometry"];
		for ( NSString * g in geom ) {
			if ( [g isEqualToString:geometry] ) {
				match = YES;
				break;
			}
		}
		if ( !match )
			return;

		__block BOOL wildcard = NO;
		NSDictionary * keyvals = dict[ @"tags" ];
		match = keyvals.count ? YES : NO;
		[keyvals enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop2) {
			NSString * v = tagDict[ key ];
			if ( v ) {
				if ( [value isEqualToString:v] ) {
					return;
				}
				if ( [value isEqualToString:@"*"] ) {
					wildcard = YES;
					return;
				}
			}
			match = NO;
			*stop2 = YES;
		}];
		if ( match ) {
			NSString * matchScoreText = dict[ @"matchScore" ];
			double matchScore = matchScoreText ? matchScoreText.doubleValue : wildcard ? 0.8 : 1.0;
			if ( matchScore > bestMatchScore ) {
				bestMatchDict = dict;
				bestMatchScore = matchScore;
			}
		}
	}];

	_featureName = bestMatchDict[ @"name"];

	// Always start with Type and Name
	CommonTag * typeTag = [CommonTag tagWithName:@"Type" tagKey:nil placeholder:@"" keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeNone presets:@[@"",@""]];
	CommonTag * nameTag = [CommonTag tagWithName:@"Name" tagKey:@"name" placeholder:@"common name" keyboard:UIKeyboardTypeDefault capitalize:UITextAutocapitalizationTypeWords presets:nil];
	CommonGroup * typeGroup = [CommonGroup groupWithName:@"Type" tags:@[ typeTag, nameTag ] ];
	_sectionList = [NSMutableArray arrayWithArray:@[ typeGroup ]];

	// Add user-defined presets
	NSMutableArray * customGroup = [NSMutableArray new];
	for ( CustomPreset * custom in [CustomPresetList shared] ) {
		if ( custom.appliesToKey.length ) {
			NSString * v = tagDict[ custom.appliesToKey ];
			if ( v && (custom.appliesToValue.length == 0 || [v isEqualToString:custom.appliesToValue]) ) {
				// accept
			} else {
				continue;
			}
		}
		[customGroup addObject:custom];
	}
	if ( customGroup.count ) {
		CommonGroup * group = [CommonGroup groupWithName:nil tags:customGroup];
		[_sectionList addObject:group];
	}

	// Add presets specific to the type
	NSMutableSet * fieldSet = [NSMutableSet new];
	for ( NSString * field in bestMatchDict[@"fields"] ) {

		if ( [fieldSet containsObject:field] )
			continue;
		[fieldSet addObject:field];

		CommonGroup * group = [self groupForField:field geometry:geometry update:update];
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

	// Add generic presets
	NSArray * extras = @[ @"elevation", @"note", @"phone", @"website", @"wheelchair", @"wikipedia" ];
	CommonGroup * extraGroup = [CommonGroup groupWithName:@"Other" tags:nil];
	for ( NSString * field in extras ) {
		CommonGroup * group = [self groupForField:field geometry:geometry update:update];
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

@end



@implementation CustomPreset
-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)key placeholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize presets:(NSArray *)presets
{
	return [super initWithName:name tagKey:key placeholder:placeholder keyboard:keyboard capitalize:capitalize presets:presets];
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





@implementation PrimaryTag

+(UIImage *)iconForName:(NSString *)name
{
	if ( name == nil )
		return nil;
	NSString * path = [NSString stringWithFormat:@"poi/%@-24", name];
	UIImage * icon = [UIImage imageNamed:path];
	return icon;
}

-(instancetype)initWithKeyValue:(NSString *)keyValue
{
	self = [super init];
	if ( self ) {
		NSDictionary * dict;
		BOOL isCategory = [keyValue hasPrefix:@"category-"];
		if ( isCategory ) {
			dict = g_categoriesDict[ keyValue ];
		} else {
			dict = g_presetsDict[ keyValue ];
		}

		_friendlyName = dict[ @"name" ];
		_summary	= nil;
		NSArray * a = [keyValue componentsSeparatedByString:@"/"];
		_key		= isCategory ? nil : a[0];
		_value		= isCategory ? nil : a.count > 1 ? a[1] : nil;
		_terms		= dict[ @"terms" ];
		_geometry	= dict[ @"geometry" ];


		TagInfo * tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForKey:_key value:_value];
		_icon = tagInfo.icon;
		if ( _icon == nil ) {
			_icon = [PrimaryTag iconForName:dict[ @"icon" ]];
		}


		if ( isCategory ) {
			NSArray * m = dict[ @"members" ];
			NSMutableArray * m2 = [NSMutableArray new];
			for ( NSString * kv in m ) {
				PrimaryTag * t = [[PrimaryTag alloc] initWithKeyValue:kv];
				[m2 addObject:t];
			}
			_members = m2;
		}
	}
	return self;
}

@end



@implementation PrimaryTagDatabase

+(instancetype)shared
{
	static PrimaryTagDatabase * g_shared = nil;
	if ( g_shared == nil ) {
		g_shared = [PrimaryTagDatabase new];
	}
	return g_shared;
}

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		[CommonTagList initializeDictionaries];

		_primaryKeyValueDict = [NSMutableDictionary new];
	}
	return self;
}

-(NSArray *)primaryTagsForMemberList:(NSArray *)nameList
{
	NSMutableArray * list = [NSMutableArray new];
	for ( NSString * name in nameList ) {
		PrimaryTag * tag = _primaryKeyValueDict[ name ];
		if ( tag == nil ) {
			tag = [[PrimaryTag alloc] initWithKeyValue:name];
			[_primaryKeyValueDict setObject:tag forKey:name];
		}
		DbgAssert( tag );
		[list addObject:tag];
	}
	return list;
}

-(NSArray *)primaryTagsForGeometry:(NSString *)geometry
{
	NSArray * list = g_defaultsDict[geometry];
	list = [self primaryTagsForMemberList:list];
	return list;
}

-(NSMutableArray *)primaryTagsForCategory:(PrimaryTag *)category matching:(NSString *)searchText;
{
	NSMutableArray * list = [NSMutableArray new];
	if ( category ) {
		for ( PrimaryTag * tag in category.members ) {
			BOOL add = NO;
			if ( [tag.friendlyName rangeOfString:searchText].length > 0 ) {
				add = YES;
			} else {
				for ( NSString * term in tag.terms ) {
					if ( [term rangeOfString:searchText].length > 0 ) {
						add = YES;
						break;
					}
				}
			}
			if ( add ) {
				[list addObject:tag];
			}
		}
	} else {
		[g_presetsDict enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSDictionary * dict, BOOL *stop) {
			BOOL add = NO;
			if ( [name rangeOfString:searchText].length > 0 ) {
				add = YES;
			} else {
				for ( NSString * term in dict[ @"terms" ] ) {
					if ( [term rangeOfString:searchText].length > 0 ) {
						add = YES;
						break;
					}
				}
			}
			if ( add ) {
				if ( dict[@"suggestion"] == nil ) {
					[list addObject:[[PrimaryTag alloc] initWithKeyValue:name]];
				}
			}
		}];
	}
	return list;
}

-(PrimaryTag *)primaryTagForKey:(NSString *)key value:(NSString *)value
{
	NSString * kv = [NSString stringWithFormat:@"%@/%@",key,value];
	PrimaryTag * best = [[PrimaryTag alloc] initWithKeyValue:kv];
	return best;
}


@end

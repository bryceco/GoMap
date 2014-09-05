//
//  CommonTagList.m
//  Go Map!!
//
//  Created by Bryce on 9/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "iosapi.h"
#import "CommonTagList.h"
#import "TagInfo.h"


@implementation CommonTag
-(instancetype)initWithName:(NSString *)name tag:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets
{
	self = [super init];
	if ( self ) {
		_name			= name;
		_tag			= tag;
		_placeholder	= placeholder;
		_presetList		= presets;
	}
	return self;
}
+(instancetype)tagWithName:(NSString *)name tag:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets
{
	return [[CommonTag alloc] initWithName:name tag:tag placeholder:placeholder presets:presets];
}
@end


@implementation CommonTagList

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

-(instancetype)init
{
	self = [super init];
	if ( self ) {
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
	}
	return self;
}

-(NSInteger)sectionCount
{
	return _sectionList.count;
}

-(NSString *)sectionNameAtIndex:(NSInteger)index
{
	return _sectionNameList[ index ];
}

-(NSInteger)tagsInSection:(NSInteger)index
{
	NSArray * tags = _sectionList[ index ];
	return tags.count;
}

-(CommonTag *)tagAtSection:(NSInteger)section row:(NSInteger)row
{
	NSArray * tags = _sectionList[ section ];
	CommonTag * tag = tags[ row ];
	return tag;
}

-(CommonTag *)tagAtIndexPath:(NSIndexPath *)indexPath
{
	return [self tagAtSection:indexPath.section row:indexPath.row];
}

-(void)insertTag:(CommonTag *)tag atIndexPath:(NSIndexPath *)indexPath
{
	NSMutableArray * tags = _sectionList[ indexPath.section ];
	[tags insertObject:tag atIndex:indexPath.row];
}

-(void)removeTagAtIndexPath:(NSIndexPath *)indexPath
{
	NSMutableArray * tags = _sectionList[ indexPath.section ];
	[tags removeObjectAtIndex:indexPath.row];
}

@end

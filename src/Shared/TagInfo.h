//
//  TagInfo.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OsmBaseObject;

@interface TagInfo : NSObject
{
	NSImage *	_icon;
	CGImageRef	_cgIcon;
	NSInteger	_renderSize;
}
@property (strong,nonatomic)	NSString	*	key;
@property (strong,nonatomic)	NSString	*	value;
@property (strong,nonatomic)	NSString	*	friendlyName;
@property (strong,nonatomic)	NSString	*	type;
@property (strong,nonatomic)	NSString	*	belongsTo;
@property (strong,nonatomic)	NSString	*	iconName;
@property (strong,nonatomic)	NSString	*	summary;
@property (strong,nonatomic)	NSColor		*	lineColor;
@property (assign,nonatomic)	NSString	*	lineColorText;
@property (assign,nonatomic)	CGFloat			lineWidth;
@property (strong,nonatomic)	NSColor		*	areaColor;
@property (assign,nonatomic)	NSString	*	areaColorText;

-(NSString *)friendlyName2;

-(BOOL)isAddressPoint;

-(NSInteger)renderSize:(OsmBaseObject *)object;

+(NSColor *)colorForString:(NSString *)text;
+(NSString *)stringForColor:(NSColor *)color;

@end



@interface TagInfoDatabase : NSObject
{
	NSArray				*	_allTags;
	NSMutableDictionary *	_keyDict;
}
+(TagInfoDatabase *)sharedTagInfoDatabase;
+(NSMutableArray *)readXml;

-(NSSet *)allTagKeys;
-(NSSet *)allTagValuesForKey:(NSString *)key;

-(TagInfo *)tagInfoForKey:(NSString *)key value:(NSString *)value;
-(TagInfo *)tagInfoForObject:(OsmBaseObject *)object;

#if TARGET_OS_IPHONE
- (NSArray *)subitemsOfType:(NSString *)type belongTo:(NSString *)belongTo;
- (NSArray *)itemsForTag:(NSString *)type matching:(NSString *)searchText;
#else
-(NSMenu *)tagNodeMenuWithTarget:(id)target action:(SEL)action;
-(NSMenu *)tagWayMenuWithTarget:(id)target action:(SEL)action;
#endif
-(NSArray *)tagsForNodes;

-(NSArray *)cuisineStyleValues;
-(NSArray *)cuisineEthnicValues;
-(NSArray *)wifiValues;
-(NSArray *)fixmeValues;
-(NSArray *)sourceValues;

@end

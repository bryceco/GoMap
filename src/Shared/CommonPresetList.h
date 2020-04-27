//
//  CommonTagList.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/4/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
typedef int UIKeyboardType;
typedef int UITextAutocapitalizationType;
#endif


#define GEOMETRY_AREA	@"area"
#define	GEOMETRY_WAY	@"line"
#define GEOMETRY_NODE	@"point"
#define GEOMETRY_VERTEX	@"vertex"

@class RenderInfo;
@class OsmWay;


// A possible value for a tag
@interface CommonPresetValue : NSObject
@property (readonly,nonatomic) NSString	*	name;
@property (readonly,nonatomic) NSString *	details;
@property (readonly,nonatomic) NSString	*	tagValue;
-(instancetype)initWithName:(NSString *)name details:(NSString *)details tagValue:(NSString *)value;
+(instancetype)presetWithName:(NSString *)name details:(NSString *)details tagValue:(NSString *)value;
@end


// A key along with information about possible values
@interface CommonPresetKey : NSObject
@property (readonly,nonatomic) NSString					*	name;
@property (readonly,nonatomic) NSString					*	tagKey;
@property (readonly,nonatomic) NSString					*	defaultValue;
@property (readonly,nonatomic) NSString					*	placeholder;
@property (readonly,nonatomic) NSArray					*	presetList;		// array of CommonTagValue
@property (readonly,nonatomic) UIKeyboardType				keyboardType;
@property (readonly,nonatomic) UITextAutocapitalizationType	autocapitalizationType;

-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)tag defaultValue:defaultValue placeholder:(NSString *)placeholder
				   keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
					presets:(NSArray *)presets;
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)tag defaultValue:defaultValue placeholder:(NSString *)placeholder
				   keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
				   presets:(NSArray *)presets;
-(instancetype)initWithCoder:(NSCoder *)coder;
-(void)encodeWithCoder:(NSCoder *)enCoder;
@end


// A group of related tags, such as address tags, organized for display purposes
@interface CommonPresetGroup : NSObject
@property (readonly,nonatomic) 	NSString	*	name;
@property (readonly,nonatomic) 	NSArray		*	tags;	// array of CommonTagKey
@property (assign,nonatomic)	BOOL			isDrillDown;
+(instancetype)groupWithName:(NSString *)name tags:(NSArray *)tags;
@end



// A top-level group such as road, building, for building hierarchical menus
@interface CommonPresetCategory : NSObject
{
	NSString	*	_categoryName;
}
@property (readonly,nonatomic)	NSString	*	friendlyName;
@property (readonly,nonatomic)	UIImage		*	icon;
@property (readonly,nonatomic)	NSArray		*	members;
-(instancetype)initWithCategoryName:(NSString *)name;
@end


// A feature-defining tag such as amenity=shop
@interface CommonPresetFeature : NSObject
{
	NSDictionary	*	_dict;
	RenderInfo		*	_renderInfo;
}
@property (readonly,nonatomic)	NSString		*	featureName;
@property (readonly,nonatomic)	NSString		*	friendlyName;
@property (readonly,nonatomic)	NSDictionary	*	tags;
@property (readonly,nonatomic)	NSString		*	summary;
@property (readonly,nonatomic)	UIImage			*	icon;
@property (readonly,nonatomic)	NSArray			*	terms;
@property (readonly,nonatomic)	NSArray			*	geometry;
@property (readonly,nonatomic)	NSArray			*	members;
@property (readonly,nonatomic)	NSDictionary	*	addTags;
@property (readonly,nonatomic)	NSDictionary	*	removeTags;
@property (readonly,nonatomic)	BOOL				suggestion;
+(instancetype)commonTagFeatureWithName:(NSString *)name;
-(BOOL)matchesSearchText:(NSString *)text;
-(NSDictionary *)defaultValuesForGeometry:(NSString *)geometry;
@end


@interface PresetLanguages : NSObject
@property (strong,nonatomic) NSString * preferredLanguageCode;	// default or user's preferred languange

-(NSArray *)languageCodes;
-(NSString *)languageNameForCode:(NSString *)code;
-(NSString *)localLanguageNameForCode:(NSString *)code;
@end


@interface CommonPresetList : NSObject
{
	NSString		*	_featureName;
	NSMutableArray	*	_sectionList;	// array of CommonTagGroup
}

+(instancetype)sharedList;
+(NSString *)featureNameForObjectDict:(NSDictionary *)tagDict geometry:(NSString *)geometry;
+(NSArray *)featuresForGeometry:(NSString *)geometry;
+(NSArray *)featuresInCategory:(CommonPresetCategory *)category matching:(NSString *)searchText;
+(NSSet *)allTagKeys;
+(NSSet *)allTagValuesForKey:(NSString *)key;
+(NSString *)friendlyValueNameForKey:(NSString *)key value:(NSString *)value geometry:(NSString *)geometry;


-(void)setPresetsForFeature:(NSString *)feature tags:(NSDictionary *)dict geometry:(NSString *)geometry  update:(void (^)(void))update;

-(NSString *)featureName;
-(NSInteger)sectionCount;
-(NSInteger)tagsInSection:(NSInteger)index;
-(CommonPresetGroup *)groupAtIndex:(NSInteger)index;
-(CommonPresetKey *)tagAtSection:(NSInteger)section row:(NSInteger)row;
-(CommonPresetKey *)tagAtIndexPath:(NSIndexPath *)indexPath;

+(BOOL)isArea:(OsmWay *)way;
@end


@interface CustomPreset : CommonPresetKey
@property (copy,nonatomic) NSString	*	appliesToKey;
@property (copy,nonatomic) NSString	*	appliesToValue;
-(instancetype)initWithCoder:(NSCoder *)coder;
@end



@interface CustomPresetList : NSObject <NSFastEnumeration>
{
	NSMutableArray *	_list;
}

+(CustomPresetList *)shared;
-(void)load;
-(void)save;

-(NSInteger)count;
-(CustomPreset *)presetAtIndex:(NSUInteger)index;
-(void)addPreset:(CustomPreset *)preset atIndex:(NSInteger)index;
-(void)removePresetAtIndex:(NSInteger)index;
@end



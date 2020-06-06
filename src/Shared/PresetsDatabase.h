//
//  CommonPresetList.h
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


// A possible value for a preset key
@interface PresetValue : NSObject
@property (readonly,nonatomic) NSString	*	name;
@property (readonly,nonatomic) NSString *	details;
@property (readonly,nonatomic) NSString	*	tagValue;
+(instancetype)presetValueWithName:(NSString *)name details:(NSString *)details tagValue:(NSString *)value;
@end


// A key along with information about possible values
@interface PresetKey : NSObject
@property (readonly,nonatomic) NSString					*	name;
@property (readonly,nonatomic) NSString					*	tagKey;
@property (readonly,nonatomic) NSString					*	defaultValue;
@property (readonly,nonatomic) NSString					*	placeholder;
@property (readonly,nonatomic) NSArray<PresetValue *>	*	presetList;
@property (readonly,nonatomic) UIKeyboardType				keyboardType;
@property (readonly,nonatomic) UITextAutocapitalizationType	autocapitalizationType;

-(instancetype)initWithName:(NSString *)name
				 featureKey:(NSString *)tag
			   defaultValue:defaultValue
				placeholder:(NSString *)placeholder
				   keyboard:(UIKeyboardType)keyboard
				 capitalize:(UITextAutocapitalizationType)capitalize
					presets:(NSArray *)presets;
+(instancetype)presetKeyWithName:(NSString *)name
					  featureKey:(NSString *)tag
					defaultValue:defaultValue
					 placeholder:(NSString *)placeholder
						keyboard:(UIKeyboardType)keyboard
					  capitalize:(UITextAutocapitalizationType)capitalize
						 presets:(NSArray *)presets;
-(instancetype)initWithCoder:(NSCoder *)coder;
-(void)encodeWithCoder:(NSCoder *)enCoder;
@end


// A group of related tags, such as address tags, organized for display purposes
@interface PresetGroup : NSObject
@property (readonly,nonatomic) 	NSString				*	name;
@property (readonly,nonatomic) 	NSArray<PresetKey *>	*	presetKeys;
@property (assign,nonatomic)	BOOL						isDrillDown;
+(instancetype)presetGroupWithName:(NSString *)name tags:(NSArray *)tags;
@end


// A feature-defining tag such as amenity=shop
@interface PresetFeature : NSObject
{
	NSDictionary	*	_dict;
	RenderInfo		*	_renderInfo;
}
@property (readonly,nonatomic)	NSString		*	featureName;
@property (readonly,nonatomic)	NSString		*	friendlyName;
@property (readonly,nonatomic)	NSDictionary	*	tags;
@property (readonly,nonatomic)	NSString		*	summary;
@property (readonly,nonatomic)	UIImage			*	icon;
@property (readonly,nonatomic)	NSString		*	logoURL;
@property (strong,nonatomic)	UIImage			*	logoImage;
@property (readonly,nonatomic)	NSArray			*	terms;
@property (readonly,nonatomic)	NSArray			*	geometry;
@property (readonly,nonatomic)	NSArray			*	members;
@property (readonly,nonatomic)	NSDictionary	*	addTags;
@property (readonly,nonatomic)	NSDictionary	*	removeTags;
@property (readonly,nonatomic)	BOOL				suggestion;
+(instancetype)presetFeatureForFeatureName:(NSString *)name;
-(BOOL)matchesSearchText:(NSString *)text;
-(NSDictionary *)defaultValuesForGeometry:(NSString *)geometry;
@end


// A top-level group such as road, building, for building hierarchical menus
@interface PresetCategory : NSObject
{
	NSString	*	_categoryName;
}
@property (readonly,nonatomic)	NSString					*	friendlyName;
@property (readonly,nonatomic)	UIImage						*	icon;
@property (readonly,nonatomic)	NSArray<PresetFeature *>	*	members;
-(instancetype)initWithCategoryName:(NSString *)name;
@end


@interface PresetLanguages : NSObject
@property (strong,nonatomic) NSString * preferredLanguageCode;	// default or user's preferred languange

-(NSArray *)languageCodes;
-(NSString *)languageNameForCode:(NSString *)code;
-(NSString *)localLanguageNameForCode:(NSString *)code;
@end



@interface PresetsForFeature : NSObject
{
	NSString						*	_featureName;
	NSMutableArray<PresetGroup *>	*	_sectionList;
}

+(instancetype)presetsForFeature:(NSString *)featureName objectTags:(NSDictionary *)dict geometry:(NSString *)geometry  update:(void (^)(void))update;

-(NSString *)featureName;
-(NSArray<PresetGroup *> *)sectionList;
-(NSInteger)sectionCount;
-(NSInteger)tagsInSection:(NSInteger)index;

-(PresetGroup *)groupAtIndex:(NSInteger)index;
-(PresetKey *)presetAtSection:(NSInteger)section row:(NSInteger)row;
-(PresetKey *)presetAtIndexPath:(NSIndexPath *)indexPath;
@end



@interface PresetsDatabase : NSObject
+(NSString *)featureNameForObjectDict:(NSDictionary *)tagDict geometry:(NSString *)geometry;
+(NSArray<PresetFeature *> *)featuresAndCategoriesForGeometry:(NSString *)geometry;
+(NSArray<PresetFeature *> *)featuresInCategory:(PresetCategory *)category matching:(NSString *)searchText;
+(NSSet<NSString *> *)allTagKeys;
+(NSSet<NSString *> *)allTagValuesForKey:(NSString *)key;
+(NSSet<NSString *> *)allFeatureKeys;
+(NSString *)friendlyValueNameForKey:(NSString *)key value:(NSString *)value geometry:(NSString *)geometry;
+(BOOL)isArea:(OsmWay *)way;
@end


@interface CustomPreset : PresetKey
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



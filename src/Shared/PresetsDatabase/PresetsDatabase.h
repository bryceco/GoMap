//
//  PresetsDatabase.h
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
-(NSString *)prettyNameForTagValue:(NSString *)value;
-(NSString *)tagValueForPrettyName:(NSString *)value;
@end


// A group of related tags, such as address tags, organized for display purposes
@interface PresetGroup : NSObject
@property (readonly,nonatomic) 	NSString				*	name;
@property (readonly,nonatomic) 	NSArray<PresetKey *>	*	presetKeys;
@property (assign,nonatomic)	BOOL						isDrillDown;
+(instancetype)presetGroupWithName:(NSString *)name tags:(NSArray *)tags;
@end

// A feature-defining tag such as amenity=shop
@interface PresetFeature(Extension)
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


// All presets for a feature, for presentation in Common Tags table view
@interface PresetsForFeature : NSObject
{
	NSString						*	_featureName;
	NSMutableArray<PresetGroup *>	*	_sectionList;
}

+(instancetype)presetsForFeature:(PresetFeature *)feature objectTags:(NSDictionary *)dict geometry:(NSString *)geometry  update:(void (^)(void))update;

-(NSString *)featureName;
-(NSArray<PresetGroup *> *)sectionList;
-(NSInteger)sectionCount;
-(NSInteger)tagsInSection:(NSInteger)index;

-(PresetGroup *)groupAtIndex:(NSInteger)index;
-(PresetKey *)presetAtSection:(NSInteger)section row:(NSInteger)row;
-(PresetKey *)presetAtIndexPath:(NSIndexPath *)indexPath;
@end


// The entire presets database from iD
@interface PresetsDatabase(Extension)
+(NSArray<PresetFeature *> *)featuresAndCategoriesForGeometry:(NSString *)geometry;
+(NSArray<PresetFeature *> *)featuresInCategory:(PresetCategory *)category matching:(NSString *)searchText;
+(NSSet<NSString *> *)allTagKeys;
+(NSSet<NSString *> *)allTagValuesForKey:(NSString *)key;
+(NSSet<NSString *> *)allFeatureKeys;
+(BOOL)isArea:(OsmWay *)way;
+(BOOL)eligibleForAutocomplete:(NSString *)key;
@end

// A preset the user defined as a custom preset
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



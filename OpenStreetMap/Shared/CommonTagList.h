//
//  CommonTagList.h
//  Go Map!!
//
//  Created by Bryce on 9/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>


#define GEOMETRY_AREA	@"area"
#define	GEOMETRY_WAY	@"line"
#define GEOMETRY_NODE	@"point"
#define GEOMETRY_VERTEX	@"vertex"




@interface CommonPreset : NSObject
@property (readonly,nonatomic) NSString	*	name;
@property (readonly,nonatomic) NSString	*	tagValue;
-(instancetype)initWithName:(NSString *)name tagValue:(NSString *)value;
+(instancetype)presetWithName:(NSString *)name tagValue:(NSString *)value;
@end


@interface CommonTag : NSObject
@property (readonly,nonatomic) NSString					*	name;
@property (readonly,nonatomic) NSString					*	tagKey;
@property (readonly,nonatomic) NSString					*	placeholder;
@property (readonly,nonatomic) NSArray					*	presetList;		// array of CommonPreset
@property (readonly,nonatomic) UIKeyboardType				keyboardType;
@property (readonly,nonatomic) UITextAutocapitalizationType	autocapitalizationType;

-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder
				   keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
					presets:(NSArray *)presets;
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder
				   keyboard:(UIKeyboardType)keyboard capitalize:(UITextAutocapitalizationType)capitalize
				   presets:(NSArray *)presets;
-(instancetype)initWithCoder:(NSCoder *)coder;
-(void)encodeWithCoder:(NSCoder *)enCoder;
@end


@interface CommonGroup : NSObject
@property (readonly,nonatomic) NSString	*	name;
@property (readonly,nonatomic) NSArray *	tags;	// array of CommonTag
+(instancetype)groupWithName:(NSString *)name tags:(NSArray *)tags;
@end



@interface CommonTagList : NSObject
{
	NSString		*	_featureName;
	NSMutableArray	*	_sectionList;	// array of CommonGroup
}

+(instancetype)sharedList;
-(void)setPresetsForDict:(NSDictionary *)dict geometry:(NSString *)geometry  update:(void (^)(void))update;

-(NSString *)featureName;
-(NSInteger)sectionCount;
-(NSInteger)tagsInSection:(NSInteger)index;
-(CommonGroup *)groupAtIndex:(NSInteger)index;
-(CommonTag *)tagAtSection:(NSInteger)section row:(NSInteger)row;
-(CommonTag *)tagAtIndexPath:(NSIndexPath *)indexPath;
@end


@interface CustomPreset : CommonTag
@property NSString	*	appliesToKey;
@property NSString	*	appliesToValue;
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




@interface PrimaryTag : NSObject
@property (readonly,nonatomic)	NSString	*	key;
@property (readonly,nonatomic)	NSString	*	value;
@property (readonly,nonatomic)	NSString	*	friendlyName;
@property (readonly,nonatomic)	NSString	*	summary;
@property (readonly,nonatomic)	UIImage		*	icon;
@property (readonly,nonatomic)	NSArray		*	terms;
@property (readonly,nonatomic)	NSArray		*	geometry;
@property (readonly,nonatomic)	NSArray		*	members;
-(instancetype)initWithKeyValue:(NSString *)keyValue;
@end



@interface PrimaryTagDatabase : NSObject
{
	NSMutableDictionary	*	_primaryKeyValueDict;
}
+(instancetype)shared;
-(NSArray *)primaryTagsForGeometry:(NSString *)geometry;
-(PrimaryTag *)primaryTagForKey:(NSString *)key value:(NSString *)value;
-(NSMutableArray *)primaryTagsForCategory:(PrimaryTag *)category matching:(NSString *)searchText;
@end

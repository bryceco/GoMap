//
//  CommonTagList.h
//  Go Map!!
//
//  Created by Bryce on 9/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>


#define GEOMETRY_AREA	@"area"
#define	GEOMETRY_WAY	@"way"
#define GEOMETRY_NODE	@"node"
#define GEOMETRY_VERTEX	@"vertex"




@interface CommonPreset : NSObject
@property (readonly,nonatomic) NSString	*	name;
@property (readonly,nonatomic) NSString	*	tagValue;
-(instancetype)initWithName:(NSString *)name tagValue:(NSString *)value;
+(instancetype)presetWithName:(NSString *)name tagValue:(NSString *)value;
@end

@interface CommonTag : NSObject
@property NSString			*	name;
@property NSString			*	tagKey;
@property NSString			*	placeholder;
@property NSArray			*	presetList;		// array of CommonPreset

-(instancetype)initWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets;
+(instancetype)tagWithName:(NSString *)name tagKey:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets;
@end


@interface CommonGroup : NSObject
@property (readonly,nonatomic) NSString	*	name;
@property (readonly,nonatomic) NSArray *	tags;	// array of CommonTag
+(instancetype)groupWithName:(NSString *)name tags:(NSArray *)tags;
@end


@interface CommonTagList : NSObject
{
	NSMutableArray	*	_sectionList;	// array of CommonGroup
}

-(void)setPresetsForKey:(NSString *)key value:(NSString *)value geometry:(NSString *)geometry;

-(NSInteger)sectionCount;
-(NSInteger)tagsInSection:(NSInteger)index;
-(CommonGroup *)groupAtIndex:(NSInteger)index;
-(CommonTag *)tagAtSection:(NSInteger)section row:(NSInteger)row;
-(CommonTag *)tagAtIndexPath:(NSIndexPath *)indexPath;

#if 0
-(void)insertTag:(CommonTag *)tag atIndexPath:(NSIndexPath *)indexPath;
-(void)removeTagAtIndexPath:(NSIndexPath *)indexPath;
#endif
@end

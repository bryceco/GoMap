//
//  CommonTagList.h
//  Go Map!!
//
//  Created by Bryce on 9/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CommonTag : NSObject
@property NSString			*	name;
@property NSString			*	tag;
@property NSString			*	placeholder;
@property NSArray			*	presetList;

-(instancetype)initWithName:(NSString *)name tag:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets;
+(instancetype)tagWithName:(NSString *)name tag:(NSString *)tag placeholder:(NSString *)placeholder presets:(NSArray *)presets;
@end


@interface CommonTagList : NSObject
{
	NSMutableArray	*	_sectionList;
	NSMutableArray	*	_sectionNameList;
}

-(NSInteger)sectionCount;
-(NSString *)sectionNameAtIndex:(NSInteger)index;
-(NSInteger)tagsInSection:(NSInteger)index;
-(CommonTag *)tagAtSection:(NSInteger)section row:(NSInteger)row;
-(CommonTag *)tagAtIndexPath:(NSIndexPath *)indexPath;

-(void)insertTag:(CommonTag *)tag atIndexPath:(NSIndexPath *)indexPath;
-(void)removeTagAtIndexPath:(NSIndexPath *)indexPath;
@end

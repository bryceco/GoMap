//
//  POITabBarController.h
//  OSMiOS
//
//  Created by Bryce on 12/14/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface POITabBarController : UITabBarController
{
	NSString		*	_typeTag;
	NSString		*	_typeValue;
}
@property (strong,nonatomic)	NSMutableDictionary *	keyValueDict;
@property (readonly,nonatomic)	NSArray				*	typeList;
@property (strong,nonatomic)	NSMutableArray		*	relationList;
@property (assign,nonatomic)	id						selection;

- (void)setType:(NSString *)tag value:(NSString *)value byUser:(BOOL)byUser;

- (void)commitChanges;
- (BOOL)isTagDictChanged;
@end

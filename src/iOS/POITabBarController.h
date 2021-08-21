//
//  POITabBarController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/14/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmBaseObject;

@interface POITabBarController : UITabBarController
{
	NSString		*	_typeTag;
	NSString		*	_typeValue;
}
@property (strong,nonatomic)	NSMutableDictionary *	keyValueDict;
@property (strong,nonatomic)	NSArray				*	relationList;
@property (assign,nonatomic)	OsmBaseObject		*	selection;

- (void)setType:(NSString *)tag value:(NSString *)value byUser:(BOOL)byUser;

- (void)commitChanges;
- (BOOL)isTagDictChanged;
- (BOOL)isTagDictChanged:(NSDictionary *)newDictionary;

@end

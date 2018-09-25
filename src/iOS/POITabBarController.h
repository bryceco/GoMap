//
//  POITabBarController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmBaseObject;

@interface POITabBarController : UITabBarController
{
}
@property (strong,nonatomic)	NSMutableDictionary *	keyValueDict;
@property (strong,nonatomic)	NSArray				*	relationList;
@property (assign,nonatomic)	OsmBaseObject		*	selection;

- (void)setFeatureKey:(NSString *)key value:(NSString *)value;

- (void)commitChanges;
- (BOOL)isTagDictChanged;
- (BOOL)isTagDictChanged:(NSDictionary *)newDictionary;

@end

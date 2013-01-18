//
//  MapCSS.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TagDictionary;
@class OsmBaseObject;


@interface MapCssCondition : NSObject
@property (strong,nonatomic) NSString	*	tag;
@property (strong,nonatomic) NSString	*	value;
@property (strong,nonatomic) NSString	*	relation;
-(BOOL)matchTags:(OsmBaseObject *)object;
@end

@interface MapCssSelector : NSObject
@property (strong,nonatomic) NSString		*	type;		// node, way
@property (strong,nonatomic) NSString		*	zoom;		// z19-20
@property (strong,nonatomic) NSMutableArray	*	conditions;	//
@property (strong,nonatomic) NSString		*	pseudoTag;	// "closed", "selected"
@property (strong,nonatomic) NSString		*	subpart;	//
@property (strong,nonatomic) MapCssSelector	*	contains;	// node contained in a way
-(BOOL)matchObject:(OsmBaseObject *)object zoom:(NSInteger)zoom;
@end

@interface MapCssRule : NSObject
@property (strong,nonatomic) NSArray		*	selectors;
@property (strong,nonatomic) NSDictionary	*	properties;
-(NSSet *)matchObject:(OsmBaseObject *)object zoom:(NSInteger)zoom;
@end

@interface MapCSS : NSObject
@property (strong,nonatomic) NSArray	*	rules;
+(id)sharedInstance;
-(BOOL)parse:(NSError **)error;
-(NSDictionary *)matchObject:(OsmBaseObject *)object zoom:(NSInteger)zoom;
@end

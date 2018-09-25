//
//  KeyChain.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KeyChain : NSObject

+ (NSString *)getStringForIdentifier:(NSString *)identifier;
+ (BOOL)setString:(NSString *)value forIdentifier:(NSString *)identifier;
+ (void)deleteStringForIdentifier:(NSString *)identifier;

@end

//
//  WikiPage.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/26/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WikiPage : NSObject

+(instancetype)shared;

- (void)bestWikiPageForKey:(NSString *)tagKey
					 value:(NSString *)tagValue
				  language:(NSString *)language
				completion:(void (^)(NSURL * url))completion;

@end

NS_ASSUME_NONNULL_END

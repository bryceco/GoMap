//
//  aes.h
//  Go Map!!
//
//  Created by Bryce on 3/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface aes : NSObject

+(NSString *)encryptString:(NSString *)string;
+(NSString *)decryptString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END

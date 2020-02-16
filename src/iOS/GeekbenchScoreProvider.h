//
//  GeekbenchScoreProvider.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/16/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GeekbenchScoreProviding

- (double)geekbenchScore;

@end

@interface GeekbenchScoreProvider : NSObject <GeekbenchScoreProviding>

@end

NS_ASSUME_NONNULL_END

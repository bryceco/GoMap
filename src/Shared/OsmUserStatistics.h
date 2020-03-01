//
//  OsmUserStatistics.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 3/1/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OsmUserStatistics : NSObject
@property (strong,nonatomic)    NSString    *    user;
@property (strong,nonatomic)    NSDate        *    lastEdit;
@property (assign,nonatomic)    NSInteger        editCount;
@property (strong,nonatomic)    NSMutableSet *    changeSets;
@property (assign,nonatomic)    NSInteger        changeSetsCount;
@end

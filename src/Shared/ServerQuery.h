//
//  ServerQuery.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 3/1/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ServerQuery : NSObject
@property (strong,nonatomic)    NSMutableArray *    quadList;
@property (assign,nonatomic)    OSMRect                rect;
@end

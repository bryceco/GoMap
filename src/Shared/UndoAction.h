//
//  UndoAction.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UndoAction : NSObject <NSCoding>
@property (readonly,nonatomic)  NSString        *       selector;
@property (readonly,nonatomic)  id                      target;
@property (readonly,nonatomic)  NSArray         *       objects;
@property (assign,nonatomic)    NSInteger               group;

-(instancetype)initWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects;
-(void)performAction;
@end

NS_ASSUME_NONNULL_END

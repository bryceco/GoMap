//
//  NSMutableArray+PartialSort.h
//  OpenStreetMap
//
//  Created by Bryce on 1/16/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableArray (PartialSort)
-(void)partialSortK:(NSInteger)k compare:(BOOL (*)(id o1, id o2))lessThan;
@end

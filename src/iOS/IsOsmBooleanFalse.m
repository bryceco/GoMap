//
//  IsOsmBooleanFalse.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "IsOsmBooleanFalse.h"

BOOL IsOsmBooleanFalse( NSString * value )
{
    if ( [value respondsToSelector:@selector(boolValue)] ) {
        BOOL b = [value boolValue];
        return !b;
    }
    if ( [value isEqualToString:@"false"] )
        return YES;
    if ( [value isEqualToString:@"no"] )
        return YES;
    if ( [value isEqualToString:@"0"] )
        return YES;
    return NO;
}

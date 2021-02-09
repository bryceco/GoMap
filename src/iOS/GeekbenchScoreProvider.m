//
//  GeekbenchScoreProvider.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/16/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "GeekbenchScoreProvider.h"

#import <sys/utsname.h>

@implementation GeekbenchScoreProvider

-(double)geekbenchScore
{
    static double score = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct utsname systemInfo = { 0 };
        uname(&systemInfo);
        NSString * name = [[NSString alloc] initWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        NSDictionary * dict = @{
                                @"x86_64"    :    @4000,                // Simulator
                                @"i386"      :    @4000,                // Simulator

                                @"iPad5,4"     :    @0,                    // iPad Air 2
                                @"iPad4,5"   :    @2493,                // iPad Mini (2nd Generation iPad Mini - Cellular)
                                @"iPad4,4"   :    @2493,                // iPad Mini (2nd Generation iPad Mini - Wifi)
                                @"iPad4,2"   :    @2664,                // iPad Air 5th Generation iPad (iPad Air) - Cellular
                                @"iPad4,1"   :    @2664,                // iPad Air 5th Generation iPad (iPad Air) - Wifi
                                @"iPad3,6"   :    @1402,                // iPad 4 (4th Generation)
                                @"iPad3,5"   :    @1402,                // iPad 4 (4th Generation)
                                @"iPad3,4"   :    @1402,                // iPad 4 (4th Generation)
                                @"iPad3,3"   :    @492,                // iPad 3 (3rd Generation)
                                @"iPad3,2"   :    @492,                // iPad 3 (3rd Generation)
                                @"iPad3,1"   :    @492,                // iPad 3 (3rd Generation)
                                @"iPad2,7"   :    @490,                // iPad Mini (Original)
                                @"iPad2,6"   :    @490,                // iPad Mini (Original)
                                @"iPad2,5"   :    @490,                // iPad Mini (Original)
                                @"iPad2,4"   :    @492,                // iPad 2
                                @"iPad2,3"   :    @492,                // iPad 2
                                @"iPad2,2"   :    @492,                // iPad 2
                                @"iPad2,1"   :    @492,                // iPad 2

                                @"iPhone7,2" :    @2855,                // iPhone 6+
                                @"iPhone7,1" :    @2879,                // iPhone 6
                                @"iPhone6,2" :    @2523,                // iPhone 5s (model A1457, A1518, A1528 (China), A1530 | Global)
                                @"iPhone6,1" :    @2523,                // iPhone 5s model A1433, A1533 | GSM)
                                @"iPhone5,4" :    @1240,                // iPhone 5c (model A1507, A1516, A1526 (China), A1529 | Global)
                                @"iPhone5,3" :    @1240,                // iPhone 5c (model A1456, A1532 | GSM)
                                @"iPhone5,2" :    @1274,                // iPhone 5 (model A1429, everything else)
                                @"iPhone5,1" :    @1274,                // iPhone 5 (model A1428, AT&T/Canada)
                                @"iPhone4,1" :    @405,                // iPhone 4S
                                @"iPhone3,1" :    @206,                // iPhone 4
                                @"iPhone2,1" :    @150,                // iPhone 3GS

                                @"iPod5,1"   :    @410,                // iPod Touch (Fifth Generation)
                                @"iPod4,1"   :    @209,                // iPod Touch (Fourth Generation)
                            };
        NSString * value = [dict objectForKey:name];
        if ( [value isKindOfClass:[NSNumber class]] ) {
            score = value.doubleValue;
        }
        if ( score == 0 ) {
            score = 2500;
        }
    });
    return score;
}

@end

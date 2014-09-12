//
//  MANSDataAdditions.h
//  Creatures
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSData (MANSDataAdditions)

- (NSData *)zlibCompressed;
- (NSData *)zlibDecompressed;

@end

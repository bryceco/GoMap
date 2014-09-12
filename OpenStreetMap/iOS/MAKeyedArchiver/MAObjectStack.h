//
//  MAObjectStack.h
//  MAKeyedArchiver
//
//  Created by Michael Ash on Thu Nov 20 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MAObjectStack : NSObject {
	id *stack;
	unsigned capacity;
	unsigned top;
}

- (void)push:obj;
- pop;
- peek;
- (BOOL)isEmpty;

@end

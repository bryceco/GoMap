//
//  RotatingNavigationController.m
//  Go Map!!
//
//  Created by Bryce on 2/21/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "RotatingNavigationController.h"

@implementation RotatingNavigationController


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (BOOL)shouldAutorotate
{
	return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskAll;
}

@end

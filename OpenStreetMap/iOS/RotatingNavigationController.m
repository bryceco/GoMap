//
//  RotatingNavigationController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/21/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
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

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskAll;
}

@end

//
//  CreditsViewController.m
//  OSMiOS
//
//  Created by Bryce on 12/25/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "CreditsViewController.h"

@implementation CreditsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	_textView.editable = NO;
	_textView.layer.cornerRadius = 10.0;
}

@end

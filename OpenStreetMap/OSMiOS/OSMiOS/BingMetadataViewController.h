//
//  BingMetadataViewController.h
//  OSMiOS
//
//  Created by Bryce on 1/6/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BingMetadataViewController : UIViewController
@property (assign,nonatomic)	IBOutlet UIActivityIndicatorView *	activityIndicator;
@property (assign,nonatomic)	IBOutlet UITextView				*	textView;

-(IBAction)cancel:(id)sender;

@end

//
//  NewTileServerViewController.h
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AerialService;

@interface AerialEditViewController : UITableViewController <UITextFieldDelegate>
{
	IBOutlet UITextField *	nameField;
	IBOutlet UITextField *	urlField;
	IBOutlet UITextField *	tileServersField;
	IBOutlet UITextField *	zoomField;
}

@property NSString * name;
@property NSString * url;
@property NSString * tileServers;
@property NSNumber * zoom;

@property (copy) void (^completion)(AerialService * service);

-(IBAction)contentChanged:(id)sender;
-(IBAction)done:(id)sender;
-(IBAction)cancel:(id)sender;

@end

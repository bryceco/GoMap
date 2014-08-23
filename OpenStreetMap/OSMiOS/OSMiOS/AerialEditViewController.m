//
//  NewTileServerViewController.m
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "AerialList.h"
#import "AerialEditViewController.h"
#import "UITableViewCell+FixConstraints.h"

@interface AerialEditViewController ()
@end

@implementation AerialEditViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	nameField.text = self.name;
	urlField.text = self.url;
	tileServersField.text = self.tileServers;
	zoomField.text = [self.zoom stringValue];
}

-(IBAction)done:(id)sender
{
	// remove white space from subdomain list
	NSMutableArray * a = [[tileServersField.text componentsSeparatedByString:@","] mutableCopy];
	for ( NSInteger i = 0; i < a.count; ++i ) {
		a[i] = [a[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	NSString * tileServers = [a componentsJoinedByString:@","];

	AerialService * service = [AerialService aerialWithName:[nameField.text	stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
																	url:[urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
																servers:tileServers
																maxZoom:[zoomField.text integerValue]];
	self.completion(service);

	[self.navigationController popViewControllerAnimated:YES];
}

-(IBAction)cancel:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

-(IBAction)contentChanged:(id)sender
{
	if ( nameField.text.length > 0 && urlField.text.length > 0 ) {
		self.navigationItem.rightBarButtonItem.enabled = YES;
	} else {
		self.navigationItem.rightBarButtonItem.enabled = NO;
	}
}


@end

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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

-(IBAction)done:(id)sender
{
	// remove white space from subdomain list
	NSMutableArray * subdomains = [[tileServersField.text componentsSeparatedByString:@","] mutableCopy];
	for ( NSInteger i = 0; i < subdomains.count; ++i ) {
		subdomains[i] = [subdomains[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}

	AerialService * service = [AerialService aerialWithName:[nameField.text	stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
																	url:[urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
																subdomains:subdomains
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

//
//  NewTileServerViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
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
	zoomField.text = [self.zoom stringValue];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

-(BOOL)isBannedURL:(NSString *)url
{
	NSString * pattern = @".*\\.google(apis)?\\..*/(vt|kh)[\\?/].*([xyz]=.*){3}.*";
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
	NSRange range   = [regex rangeOfFirstMatchInString:url options:0 range:NSMakeRange(0,url.length)];
	if ( range.location != NSNotFound )
		return YES;
	return NO;
}

-(IBAction)done:(id)sender
{
	// remove white space from subdomain list
	NSString * url = [urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	url = [url stringByReplacingOccurrencesOfString:@"%7B" withString:@"{"];
	url = [url stringByReplacingOccurrencesOfString:@"%7D" withString:@"}"];

	if ( [self isBannedURL:urlField.text] )
		return;

	NSString * identifier = url;

	AerialService * service = [AerialService aerialWithName:[nameField.text	stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
												 			identifier:identifier
																	url:url
																maxZoom:[zoomField.text integerValue]
																roundUp:YES
																wmsProjection:nil
																polygon:NULL
											   				attribString:nil
												 			attribIcon:nil
												  			 attribUrl:nil];
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
	BOOL allowed = NO;
	if ( nameField.text.length > 0 && urlField.text.length > 0 ) {
		if ( ![self isBannedURL:urlField.text] ) {
			allowed = YES;
		}
	}
	self.navigationItem.rightBarButtonItem.enabled = allowed;
}

@end

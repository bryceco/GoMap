//
//  UploadTableViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 1/7/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <MessageUI/MessageUI.h>

#import "AppDelegate.h"
#import "MapView.h"
#import "EditorMapLayer.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "UploadTableViewController.h"
#import "UITableViewCell+FixConstraints.h"


@implementation UploadTableViewController


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	MapView * mapView = [(AppDelegate *)[[UIApplication sharedApplication] delegate] mapView];
	_mapData = mapView.editorLayer.mapData;

	_sectionList = [[_mapData createChangeset] mutableCopy];
	if ( _sectionList == nil ) {
		_commitButton.enabled = NO;
	} else {
		_commitButton.enabled = YES;
	}

	_commentTextView.text = [[NSUserDefaults standardUserDefaults] objectForKey:@"uploadComment"];

	_sendMailButton.enabled = (_sectionList != nil);
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	[[NSUserDefaults standardUserDefaults] setObject:_commentTextView.text forKey:@"uploadComment"];
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ( [text isEqualToString:@"\n"] ) {
		[textView resignFirstResponder];
		return NO;
	}
	return YES;
}

- (IBAction)commit:(id)sender
{
	[_progressView startAnimating];
	[_commitButton setEnabled:NO];
	[_cancelButton setEnabled:NO];

	AppDelegate * appDelegate = (id)[[UIApplication sharedApplication] delegate];
	_mapData.credentialsUserName = appDelegate.userName;
	_mapData.credentialsPassword = appDelegate.userPassword;

	NSString * comment = _commentTextView.text;
	comment = [comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	[_mapData uploadChangeset:comment completion:^(NSString * error){
		[_progressView stopAnimating];
		[_commitButton setEnabled:YES];
		[_cancelButton setEnabled:YES];
		if ( error ) {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"Unable to upload changes" message:error delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
		} else {
			[self dismissViewControllerAnimated:YES completion:nil];
		}
	}];
}

-(IBAction)sendMail:(id)sender
{
	if ( [MFMailComposeViewController canSendMail] ) {
		MFMailComposeViewController * mail = [[MFMailComposeViewController alloc] init];
		mail.mailComposeDelegate = self;
		[mail setSubject:@"OSMiOS changeset"];
		NSString * xml = [_mapData changesetAsXml];
		[mail addAttachmentData:[xml dataUsingEncoding:NSUTF8StringEncoding] mimeType:@"application/xml" fileName:@"osmChange.osc"];
		[self presentViewController:mail animated:YES completion:nil];
	} else {
		UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"Cannot compose message" message:@"Mail delivery is not available on this device" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1 + _sectionList.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( section == 0 ) {
		return @"Changeset comment";
	}
	NSArray * a = _sectionList[ section - 1 ];
	NSString * type = a[0];
	static NSDictionary * dict = nil;
	if ( dict == nil ) {
		dict = @{
			@"createNode"		:	@"Create Node",
			@"modifyNode"		:	@"Modify Node",
			@"deleteNode"		:	@"Delete Node",
			@"createWay"		:	@"Create Way",
			@"modifyWay"		:	@"Modify Way",
			@"deleteWay"		:	@"Delete Way",
			@"createRelation"	:	@"Create Relation",
			@"modifyRelation"	:	@"Modify Relation",
			@"deleteRelation"	:	@"Delete Relation"
		};
	}
	return [dict objectForKey:type];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section == 0 )
		return 1;
	NSArray * a = _sectionList[ section - 1 ];
	NSArray * objList = a[1];
	return objList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {
		static NSString *CellIdentifier = @"commentCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
		return cell;
	}

	static NSString *CellIdentifier = @"objectCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
	NSArray * a = _sectionList[ indexPath.section - 1 ];
	NSArray * objList = a[1];
	OsmBaseObject * object = objList[ indexPath.row ];
	NSString * type = object.isNode ? @"Node" : object.isWay ? @"Way" : @"Relation";
	cell.textLabel.text = [NSString stringWithFormat:@"%@ %@",type, object.ident];
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		// Delete the row from the data source
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	} else if (editingStyle == UITableViewCellEditingStyleInsert) {
		// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
	}   
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
}

@end

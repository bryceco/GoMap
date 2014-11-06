//
//  NotesTableViewController.m
//  Go Map!!
//
//  Created by Bryce on 11/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <MapKit/MapKit.h>

#import "Notes.h"
#import "NotesTableViewController.h"


@interface NotesCommentCell : UITableViewCell
@property (strong,nonatomic)	IBOutlet	UILabel		*	date;
@property (strong,nonatomic)	IBOutlet	UILabel		*	user;
@property (strong,nonatomic)	IBOutlet	UILabel		*	comment;
@property (strong,nonatomic)	IBOutlet	UIView		*	commentBackground;
@end
@implementation NotesCommentCell
@end

@interface NotesResolveCell : UITableViewCell
@property (strong,nonatomic)	IBOutlet	UITextView		*	text;
@property (strong,nonatomic)	IBOutlet	UIButton		*	commentButton;
@property (strong,nonatomic)	IBOutlet	UIButton		*	resolveButton;
@end
@implementation NotesResolveCell
@end


@implementation NotesTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( section == 0 )
		return @"Note History";
	else
		return @"Update";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return section == 0 ? self.note.comments.count : 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {
		NotesCommentCell *cell = (id) [tableView dequeueReusableCellWithIdentifier:@"noteCommentCell" forIndexPath:indexPath];
		OsmNoteComment * comment = self.note.comments[ indexPath.row ];
		cell.date.text		= comment.date;
		cell.user.text		= [NSString stringWithFormat:@"%@ - %@", comment.user ?: @"anonymous", comment.action];
		if ( comment.text.length == 0 ) {
			cell.commentBackground.hidden	= YES;
			cell.comment.text				= nil;
		} else {
			cell.commentBackground.hidden = NO;
			cell.commentBackground.layer.cornerRadius		= 5;
			cell.commentBackground.layer.backgroundColor	= [UIColor colorWithRed:0.9 green:0.9 blue:1.0 alpha:1.0].CGColor;
			cell.commentBackground.layer.borderColor		= UIColor.blackColor.CGColor;
			cell.commentBackground.layer.borderWidth		= 1.0;
			cell.commentBackground.layer.masksToBounds		= YES;
			cell.comment.text	= comment.text;
		}
		return cell;
	} else if ( indexPath.row == 0 ) {
		NotesResolveCell *cell = (id) [tableView dequeueReusableCellWithIdentifier:@"noteResolveCell" forIndexPath:indexPath];
		cell.text.layer.cornerRadius	= 5.0;
		cell.text.layer.borderColor		= UIColor.blackColor.CGColor;
		cell.text.layer.borderWidth		= 1.0;
		cell.text.delegate				= self;
		cell.text.text					= _newComment;
		cell.commentButton.enabled		= NO;
		return cell;
	} else {
		UITableViewCell *cell = (id) [tableView dequeueReusableCellWithIdentifier:@"noteDirectionsCell" forIndexPath:indexPath];
		return cell;
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[self.view endEditing:YES];

	if ( indexPath.section == 1 && indexPath.row == 1 ) {
		// get directions
		CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(self.note.lat, self.note.lon);
		MKPlacemark * placemark = [[MKPlacemark alloc] initWithCoordinate:coordinate addressDictionary:nil];
		MKMapItem * note = [[MKMapItem alloc] initWithPlacemark:placemark];
		[note setName:@"OSM Note"];
		MKMapItem * current = [MKMapItem mapItemForCurrentLocation];
		NSDictionary * options = @{ MKLaunchOptionsDirectionsModeKey : MKLaunchOptionsDirectionsModeDriving };
		[MKMapItem openMapsWithItems:@[current, note] launchOptions:options];
	}
}


-(void)commentAndResolve:(BOOL)resolve sender:(id)sender
{
	NotesResolveCell * cell = (id)[sender superview];
	while ( cell && ![cell isKindOfClass:[NotesResolveCell class]] )
		cell = (id) [cell superview];
	if ( cell ) {
		NSString * s = [cell.text.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
	}
}

- (IBAction)doComment:(id)sender
{
	[self commentAndResolve:NO sender:sender];
}

- (IBAction)doResolve:(id)sender
{
	[self commentAndResolve:YES sender:sender];
}

- (void)textViewDidChange:(UITextView *)textView
{
	NotesResolveCell * cell = (id)[textView superview];
	while ( cell && ![cell isKindOfClass:[NotesResolveCell class]] )
		cell = (id) [cell superview];
	if ( cell ) {
		_newComment = cell.text.text;
		NSString * s = [_newComment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		cell.commentButton.enabled = s.length > 0;
	}
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {
		OsmNoteComment * comment = self.note.comments[ indexPath.row ];

		if ( comment.text.length > 0 ) {
			NSMutableParagraphStyle * paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
			[paragraphStyle setLineBreakMode:NSLineBreakByWordWrapping];

			NSDictionary * attrs = @{
									 NSFontAttributeName : [UIFont systemFontOfSize:17],
									 NSParagraphStyleAttributeName : paragraphStyle
									 };
			CGRect rc = [comment.text boundingRectWithSize:CGSizeMake(self.view.bounds.size.width-60, 5000) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:attrs context:nil];
			return ceil(rc.size.height) + 75;
		} else {
			return 55;
		}
	} else if ( indexPath.row == 0 ) {
		return 176;
	} else {
		return 44;
	}
}

- (IBAction)done:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

//
//  POIActionsViewController.m
//  Go Map!!
//
//  Created by Bryce on 7/5/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmMapData+Orthogonalize.h"
#import "OsmObjects.h"
#import "POIActionsViewController.h"
#import "POITabBarController.h"
#import "UndoManager.h"


@interface POIActionsViewController ()
@end



@implementation POIActionsViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}


-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)done:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Actions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	EditorMapLayer * editor = appDelegate.mapView.editorLayer;

	UITableViewCell * cell = [self tableView:self.tableView cellForRowAtIndexPath:indexPath];
	if ( cell == _rectangularizeCell ) {

		POITabBarController * tabController = (id)self.tabBarController;
		OsmBaseObject * object = tabController.selection;
		if ( object.isWay ) {
			OsmWay * way = (id)object;
			if ( way.isArea ) {
				if ( [editor.mapData orthogonalize:way] ) {
					[self done:self];
					return;
				}
				UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Failed" message:@"The way is not sufficiently rectangular" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
				[alertView show];
				return;
			}
		}
		UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Invalid Selection" message:@"Requires a closed way" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
		[alertView show];

	} else {
		UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Warning" message:@"Not available for this object." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
		[alertView show];
	}
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}

@end

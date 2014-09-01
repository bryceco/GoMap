//
//  NominatumViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//


#import "AppDelegate.h"
#import "BingMapsGeometry.h"
#import "DownloadThreadPool.h"
#import "MapView.h"
#import "MapViewController.h"
#import "NominatumViewController.h"



@implementation NominatumViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	_activityIndicator.color = UIColor.blackColor;
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[_searchBar becomeFirstResponder];

	_historyArray = [[NSUserDefaults standardUserDefaults] objectForKey:@"searchHistory"];
}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[[NSUserDefaults standardUserDefaults] setObject:_historyArray forKey:@"searchHistory"];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _searchBar.text.length ? _resultsArray.count : _historyArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];

	if ( _searchBar.text.length ) {
		NSDictionary * dict = [_resultsArray objectAtIndex:indexPath.row];
		cell.textLabel.text = [dict objectForKey:@"display_name"];
	} else {
		cell.textLabel.text = _historyArray[ indexPath.row ];
	}
    return cell;
}

- (IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchBar.text.length == 0 ) {
		// history item
		_searchBar.text = _historyArray[ indexPath.row ];
		[self searchBarSearchButtonClicked:_searchBar];
		return;
	}

	NSDictionary * dict = _resultsArray[ indexPath.row ];
	NSArray * box = [dict objectForKey:@"boundingbox"];
	double lat1 = [box[0] doubleValue];
	double lat2 = [box[1] doubleValue];
	double lon1 = [box[2] doubleValue];
	double lon2 = [box[3] doubleValue];

	lat1 = (lat1+lat2)/2;
	lon1 = (lon1+lon2)/2;

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	double metersPerDegree = MetersPerDegree( lat1 );
	double minMeters = 50;
	double widthDegrees = widthDegrees = minMeters / metersPerDegree;

	// disable GPS
	if ( appDelegate.mapView.trackingLocation ) {
		[appDelegate.mapView.viewController toggleLocation:self];
	}

	[appDelegate.mapView setTransformForLatitude:lat1 longitude:lon1 width:widthDegrees];


	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Search bar delegate

- (void)searchBarCancelButtonClicked:(UISearchBar *) searchBar
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
	[searchBar resignFirstResponder];

	_resultsArray = nil;
	NSString * string = searchBar.text;
	if ( string.length == 0 ) {
		// no search
		[_searchBar performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0.1];
	} else {
		// searching
		[_activityIndicator startAnimating];
		DownloadThreadPool * pool = [DownloadThreadPool generalPool];
		NSString * text = [string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		NSString * url = [NSString stringWithFormat:@"http://nominatim.openstreetmap.org/search?q=%@&format=json",text];
		[pool dataForUrl:url completion:^(NSData * data,NSError * error){
			[_activityIndicator stopAnimating];

			if ( data && !error ) {

				/*
				 {
				 "place_id":"5639098",
				 "licence":"Data \u00a9 OpenStreetMap contributors, ODbL 1.0. http:\/\/www.openstreetmap.org\/copyright",
				 "osm_type":"node",
				 "osm_id":"585214834",
				 "boundingbox":["55.9587516784668","55.9587554931641","-3.20986247062683","-3.20986223220825"],
				 "lat":"55.9587537","lon":"-3.2098624",
				 "display_name":"Hectors, Deanhaugh Street, Stockbridge, Dean, Edinburgh, City of Edinburgh, Scotland, EH4 1NE, United Kingdom",
				 "class":"amenity",
				 "type":"pub",
				 "icon":"http:\/\/nominatim.openstreetmap.org\/images\/mapicons\/food_pub.p.20.png"
				 },
				 */

				id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
				_resultsArray = json;
				[_tableView reloadData];

				if ( _resultsArray.count > 0 ) {
					NSMutableArray * a = _historyArray ? [_historyArray mutableCopy] : [NSMutableArray new];
					[a removeObject:string];
					[a insertObject:string atIndex:0];
					while ( a.count > 20 )
						[a removeLastObject];
					_historyArray = a;
				}
				
			} else {
				// error fetching results
			}

			if ( _resultsArray.count == 0 ) {
				UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No results found",nil) message:nil delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
				[alertView show];
			}

		}];
	}
	[_tableView reloadData];
}

@end

//
//  NominatimViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//


#import "AppDelegate.h"
#import "BingMapsGeometry.h"
#import "MapView.h"
#import "NominatimViewController.h"

@interface NominatimViewController() <UITableViewDelegate>
@end

@implementation NominatimViewController


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
    [self.view endEditing:YES];
    
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

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
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

	AppDelegate * appDelegate = AppDelegate.shared;
	double metersPerDegree = MetersPerDegree( lat1 );
	double minMeters = 50;
	double widthDegrees = minMeters / metersPerDegree;

	// disable GPS
	while ( appDelegate.mapView.gpsState != GPS_STATE_NONE ) {
		[appDelegate.mapView.mainViewController toggleLocation:self];
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

		NSString * text = [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
		NSString * url = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/search?q=%@&format=json",text];
		NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				
				[_activityIndicator stopAnimating];
				
				if ( data && !error ) {
					
					/*
					 {
					 "place_id":"5639098",
					 "licence":"Data \u00a9 OpenStreetMap contributors, ODbL 1.0. https:\/\/www.openstreetmap.org\/copyright",
					 "osm_type":"node",
					 "osm_id":"585214834",
					 "boundingbox":["55.9587516784668","55.9587554931641","-3.20986247062683","-3.20986223220825"],
					 "lat":"55.9587537","lon":"-3.2098624",
					 "display_name":"Hectors, Deanhaugh Street, Stockbridge, Dean, Edinburgh, City of Edinburgh, Scotland, EH4 1NE, United Kingdom",
					 "class":"amenity",
					 "type":"pub",
					 "icon":"https:\/\/nominatim.openstreetmap.org\/images\/mapicons\/food_pub.p.20.png"
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
					UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No results found",nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
					[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
					[self presentViewController:alert animated:YES completion:nil];
				}
			});
		}];
		[task resume];
	}
	[_tableView reloadData];
}

@end

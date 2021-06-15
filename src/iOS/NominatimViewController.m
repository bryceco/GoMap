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

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
	return [UIView new];
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return 44;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
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

- (void)jumpToLat:(double)lat lon:(double)lon
{
	AppDelegate * appDelegate = AppDelegate.shared;
	double metersPerDegree = MetersPerDegree( lat );
	double minMeters = 50;
	double widthDegrees = minMeters / metersPerDegree;

	// disable GPS
	while ( appDelegate.mapView.gpsState != GPS_STATE_NONE ) {
		[appDelegate.mapView.mainViewController toggleLocation:self];
	}

	[appDelegate.mapView setTransformForLatitude:lat longitude:lon width:widthDegrees];

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

	[self jumpToLat:lat1 lon:lon1];
}

// look for a pair of non-integer numbers in the string, and jump to it if found
-(BOOL)containsLatLon:(NSString *)text
{
	text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	
	NSURLComponents * comps = [NSURLComponents componentsWithString:text];
	if ( comps.queryItems.count >= 2 ) {
		double lat = 0.0, lon = 0.0;
		for ( NSURLQueryItem * item in comps.queryItems ) {
			if ( [item.name isEqualToString:@"lat"] ) {
				lat = item.value.doubleValue;
			} else if ( [item.name isEqualToString:@"lon"] ) {
				lon = item.value.doubleValue;
			}
		}
		if ( lat && lon ) {
			[self updateHistoryWithString:[NSString stringWithFormat:@"%g,%g",lat,lon]];
			[self jumpToLat:lat lon:lon];
			return YES;
		}
	}

	NSScanner * scanner = [NSScanner scannerWithString:text];
	NSCharacterSet * digits = [NSCharacterSet characterSetWithCharactersInString:@"-0123456789"];
	NSCharacterSet * comma = [NSCharacterSet characterSetWithCharactersInString:@",/"];
	[scanner setCharactersToBeSkipped:[NSCharacterSet whitespaceCharacterSet]];
	double lat,lon;

	while ( !scanner.atEnd ) {
		[scanner scanUpToCharactersFromSet:digits intoString:NULL];
		NSInteger pos = scanner.scanLocation;
		if ( [scanner scanDouble:&lat] &&
			lat != (int)lat &&	// don't want to accidently grab the Z number
			lat > -90 && lat < 90 &&
			[scanner scanCharactersFromSet:comma intoString:NULL] &&
			[scanner scanDouble:&lon] &&
			lon != (int)lon &&
			lon >= -180 && lon <= 180 )
		{
			[self updateHistoryWithString:[NSString stringWithFormat:@"%g,%g",lat,lon]];
			[self jumpToLat:lat lon:lon];
			return YES;
		}
		if ( scanner.scanLocation == pos && !scanner.atEnd ) {
			scanner.scanLocation = pos+1;
		}
	}
	return NO;
}

-(void)updateHistoryWithString:(NSString *)string
{
	NSMutableArray * a = _historyArray ? [_historyArray mutableCopy] : [NSMutableArray new];
	[a removeObject:string];
	[a insertObject:string atIndex:0];
	while ( a.count > 20 )
		[a removeLastObject];
	_historyArray = a;
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
	} else if ( [self containsLatLon:string] ) {
		return;
	} else {
		// searching
		[_activityIndicator startAnimating];

		NSString * text = [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
		NSString * url = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/search?q=%@&format=json&limit=50",text];
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
						[self updateHistoryWithString:string];
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

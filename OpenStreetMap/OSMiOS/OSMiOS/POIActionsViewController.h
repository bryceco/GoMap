//
//  POIActionsViewController.h
//  Go Map!!
//
//  Created by Bryce on 7/5/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface POIActionsViewController : UITableViewController<UITableViewDelegate>

@property (assign,nonatomic) IBOutlet UITableViewCell	*	joinCell;
@property (assign,nonatomic) IBOutlet UITableViewCell	*	splitCell;
@property (assign,nonatomic) IBOutlet UITableViewCell	*	rectangularizeCell;
@property (assign,nonatomic) IBOutlet UITableViewCell	*	duplicateCell;
@property (assign,nonatomic) IBOutlet UITableViewCell	*	straightenCell;
@property (assign,nonatomic) IBOutlet UITableViewCell	*	reverseCell;

@end

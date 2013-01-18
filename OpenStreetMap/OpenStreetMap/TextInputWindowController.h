//
//  TextInputWindowController.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/2/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TextInputWindowController : NSWindowController
{
	void			(^_handler)(BOOL accepted);
}
@property (copy,nonatomic)		NSString *	title;
@property (copy,nonatomic)		NSString *	prompt;
@property (copy,nonatomic)		NSString *	text;
@property (copy,nonatomic)		NSString *	placeholder;

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(BOOL accepted))handler;
-(IBAction)ok:(id)sender;
-(IBAction)cancel:(id)sender;

@end

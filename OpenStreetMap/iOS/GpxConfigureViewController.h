//
//  GpxConfigureViewController.h
//  Go Map!!
//
//  Created by Bryce on 10/6/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface GpxConfigureViewController : UIViewController <UIPickerViewDelegate,UIPickerViewDataSource>
@property (assign,nonatomic) IBOutlet	UIPickerView *	pickerView;
@property (assign,nonatomic) NSNumber				*	expirationValue;
@property (copy)								void (^ completion)(NSNumber * pick);
@end

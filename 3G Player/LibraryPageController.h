//
//  LibraryPageController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LibraryPageController : UITableViewController <UIActionSheetDelegate>

- (id)initWithDirectory:(NSString*)directory title:(NSString*)title;
- (BOOL)update;

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer;
- (IBAction)handleLongPress:(UILongPressGestureRecognizer*)recognizer;
- (IBAction)handleRotation:(UIRotationGestureRecognizer*)recognizer;

@end

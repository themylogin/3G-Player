//
//  LibraryPageController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LibraryPageController : UITableViewController <UIActionSheetDelegate>

@property (nonatomic, retain) NSString* directory;

@property (nonatomic, retain) NSFileManager* fileManager;

@property (nonatomic, retain) NSArray* index;

- (id)initWithDirectory:(NSString*)directory title:(NSString*)title;
- (BOOL)update;

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer;
- (IBAction)handleLongPress:(UILongPressGestureRecognizer*)recognizer;

@end

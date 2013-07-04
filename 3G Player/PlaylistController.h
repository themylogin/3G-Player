//
//  PlaylistController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PlaylistController : UIViewController

@property (nonatomic, retain) IBOutlet UITableView* tableView;

- (void)addFile:(NSDictionary*)file afterCurrent:(BOOL)afterCurrent;
- (void)addFiles:(NSArray*)files afterCurrent:(BOOL)afterCurrent;
- (void)clear;

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer;

@end

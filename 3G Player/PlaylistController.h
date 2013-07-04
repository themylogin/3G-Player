//
//  PlaylistController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <AVFoundation/AVFoundation.h>

@interface PlaylistController : UIViewController <AVAudioPlayerDelegate>

@property (nonatomic, retain) IBOutlet UITableView* tableView;
@property (nonatomic, retain) IBOutlet UIButton* playPauseButton;
@property (nonatomic, retain) IBOutlet UISlider* positionSlider;
@property (nonatomic, retain) IBOutlet UILabel* elapsedLabel;
@property (nonatomic, retain) IBOutlet UILabel* totalLabel;
@property (nonatomic, retain) IBOutlet UIButton* repeatButton;

- (void)addFile:(NSDictionary*)file afterCurrent:(BOOL)afterCurrent;
- (void)addFiles:(NSArray*)files afterCurrent:(BOOL)afterCurrent;
- (void)clear;

- (void)playAtIndex:(int)index;

- (IBAction)handlePositionSliderTouchUpInside:(id)sender;
- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer;

@end

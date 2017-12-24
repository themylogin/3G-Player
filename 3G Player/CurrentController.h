//
//  PlaylistController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <AVFoundation/AVFoundation.h>

typedef enum { AddToTheEnd, AddAfterCurrentAlbum, AddAfterCurrentTrack, AddAfterJustAdded } AddMode;

@interface CurrentController : UIViewController <AVAudioPlayerDelegate, UIActionSheetDelegate>

@property (nonatomic, retain) IBOutlet UITableView* tableView;
@property (nonatomic, retain) IBOutlet UIView* toolbar;
@property (nonatomic, retain) IBOutlet UIButton* playPauseButton;
@property (nonatomic, retain) IBOutlet UISlider* positionSlider;
@property (nonatomic, retain) IBOutlet UILabel* elapsedLabel;
@property (nonatomic, retain) IBOutlet UILabel* totalLabel;
@property (nonatomic, retain) IBOutlet UIButton* repeatButton;
@property (nonatomic, retain) IBOutlet UIView* volumeView;
@property (nonatomic, retain) IBOutlet UIButton* scrobblerButton;
@property (nonatomic, retain) IBOutlet UILabel* scrobblerLabel;

@property (nonatomic, retain) AVAudioPlayer* player;

- (BOOL)canAddAfterAdded;
- (void)addFiles:(NSArray*)files mode:(AddMode)addMode;
- (void)clear;

- (void)playAtIndex:(long)index;

- (void)pause;

- (void)playNextTrack:(BOOL)respectRepeatTrack;
- (void)playPrevTrack:(BOOL)respectRepeatTrack;

- (void)handleSeeking:(UIEventSubtype)event;

- (IBAction)handlePlaylistLeftSwipe:(UISwipeGestureRecognizer*)recognizer;
- (IBAction)handlePlaylistLeftDoubleSwipe:(UISwipeGestureRecognizer*)recognizer;

- (IBAction)handleLongPress:(UILongPressGestureRecognizer*)recognizer;

- (IBAction)handleToolbarSwipeUp:(UISwipeGestureRecognizer*)recognizer;
- (IBAction)handleToolbarSwipeDown:(UISwipeGestureRecognizer*)recognizer;

- (NSArray*)getStatistics;

@end

//
//  PlaylistController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "CurrentController.h"

#import "Globals.h"
#import "KeepAliver.h"

#import <objc/runtime.h>

#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

#import "ASIFormDataRequest.h"
#import "CocoaAsyncSocket/GCDAsyncSocket.h"
#import "MKNumberBadgeView.h"
#import "RecommendationsForFromController.h"

static char const* const ACTIONSHEET = "ACTIONSHEET";
static char const* const BUTTONS = "BUTTONS";

static char const* const ALERTVIEW = "ALERTVIEW";
static char const* const DATA = "DATA";
static char const* const ITEMS = "ITEMS";
static char const* const POSITION = "POSITION";

@interface CurrentController ()

@property (nonatomic)         bool toolbarOpen;
@property (nonatomic, retain) MKNumberBadgeView* scrobblerBadge;

@property (nonatomic, retain) NSMutableArray* playlist;
@property (nonatomic, retain) NSMutableArray* sections;

@property (nonatomic)         long lastAddedIndex;
@property (nonatomic, retain) NSDate* lastTimeTableTouchedAt;
@property (nonatomic, retain) NSMutableArray* playlistUndoHistory;

@property (nonatomic)         long currentIndex;
@property (nonatomic, retain) NSDate* playerStartedAt;
@property (nonatomic)         int bufferMostNecessaryOverride;
@property (nonatomic)         int whenItemIsBufferedPlayAtIndex;
@property (nonatomic)         int whenItemIsBufferedPlayAtPosition;
@property (nonatomic)         bool skipScrobblingCurrent;

@property (nonatomic)         enum { RepeatDisabled, RepeatPlaylist, RepeatTrack } repeat;

@property (nonatomic, retain) NSMutableDictionary* nowPlayingInfo;

@property (nonatomic, retain) NSTimer* periodicTimer;

@property (nonatomic, retain) NSDate* bufferingProgressReportedAt;

@property (nonatomic)         bool pausedIntentionally;

@property (nonatomic)         bool pausedByLowVolume;
@property (nonatomic, retain) KeepAliver* pausedByLowVolumeKeepAliver;

@property (retain, nonatomic) IBOutlet NSLayoutConstraint *hideToolbarConstraint;

@end

@implementation CurrentController

@synthesize playlist;
@synthesize sections;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Current", NIL);
        self.tabBarItem.image = [UIImage imageNamed:@"Current"];
        
        self.toolbarOpen = NO;
        
        self.playlist = [[NSMutableArray alloc] init];
        self.sections = [[NSMutableArray alloc] init];
        
        self.lastAddedIndex = -1;
        self.lastTimeTableTouchedAt = nil;
        [self invalidatePlaylistUndoHistory];
        
        self.currentIndex = -1;
        self.player = nil;
        
        self.bufferMostNecessaryOverride = -1;
        self.whenItemIsBufferedPlayAtIndex = -1;
        self.whenItemIsBufferedPlayAtPosition = -1;
        
        self.repeat = RepeatDisabled;
        
        self.nowPlayingInfo = nil;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerStateChanged) name:@"stateChanged" object:musicFileManager];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerBufferingProgress:) name:@"bufferingProgress" object:musicFileManager];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerBufferingCompleted) name:@"bufferingCompleted" object:musicFileManager];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateCover)         
                                                     name:@"coverDownloaded"
                                                   object:musicFileManager];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onAudioRouteChange:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:[AVAudioSession sharedInstance]];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onScrobblerQueueChanged)
                                                     name:@"queueChanged"
                                                   object:scrobbler];
        
        self.bufferingProgressReportedAt = nil;
        
        NSDictionary* current = [[NSUserDefaults standardUserDefaults] objectForKey:@"current"];
        if (current)
        {
            [self.playlist addObjectsFromArray:[current objectForKey:@"playlist"]];
            [self playlistChanged];
            
            self.repeat = [[current objectForKey:@"repeat"] intValue];
            [self updateUI];
            
            long index = [[current objectForKey:@"index"] longValue];
            double position = [[current objectForKey:@"position"] doubleValue];
            if (index >= 0 && index < [self.playlist count])
            {
                [self setIndex:index position:position];
            }
        }
        
        self.pausedIntentionally = FALSE;
        
        self.pausedByLowVolume = FALSE;
        self.pausedByLowVolumeKeepAliver = [[KeepAliver alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(onSystemVolumeChanged:)
                                                      name:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                    object:nil];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self showScrobblerEnabled];
    
    self.scrobblerBadge = [[MKNumberBadgeView alloc] initWithFrame:CGRectMake(27, 0, 19, 19)];
    self.scrobblerBadge.shine = NO;
    self.scrobblerBadge.shadow = NO;
    [self onScrobblerQueueChanged];
    
    #if TARGET_IPHONE_SIMULATOR
        UISlider* volumeView = [[UISlider alloc] initWithFrame:self.volumeView.bounds];
    #else
        MPVolumeView* volumeView = [[MPVolumeView alloc] initWithFrame:self.volumeView.bounds];
    #endif
    volumeView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.volumeView addSubview:volumeView];
    [self.volumeView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[view]-0-|" options:0 metrics:nil views:@{@"view": volumeView}]];
    [self.volumeView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[view]-0-|" options:0 metrics:nil views:@{@"view": volumeView}]];
    [volumeView release];
    
    [self periodic];
    self.periodicTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(periodic) userInfo:nil repeats:YES];
}

- (void)viewDidLayoutSubviews
{
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        self.navigationController.navigationBar.barStyle = UIBarStyleBlackOpaque;
        if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
        {
            self.edgesForExtendedLayout = UIRectEdgeNone;
        }
        CGRect viewBounds = self.view.bounds;
        CGFloat topBarOffset = self.topLayoutGuide.length;
        viewBounds.origin.y = topBarOffset * -1;
        self.view.bounds = viewBounds;
        self.navigationController.navigationBar.translucent = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)periodic
{
    [self updateUI];
}

#pragma mark - Manage playlist

- (BOOL)canAddAfterAdded
{
    return self.lastAddedIndex != -1;
}

- (void)addFiles:(NSArray*)files mode:(AddMode)addMode
{
    long index = [self.playlist count];
    if (addMode == AddAfterCurrentAlbum)
    {
        for (NSDictionary* section in self.sections)
        {
            BOOL isCurrentSection = NO;
            for (NSNumber* nsi in [section objectForKey:@"files"])
            {
                long i = [nsi longValue];
                
                if (i == self.currentIndex)
                {
                    isCurrentSection = YES;
                }
                if (isCurrentSection)
                {
                    index = i + 1;
                }
            }
            if (isCurrentSection)
            {
                break;
            }
        }
    }
    if (addMode == AddAfterCurrentTrack)
    {
        index = self.currentIndex + 1;
    }
    if (addMode == AddAfterJustAdded && self.lastAddedIndex != -1)
    {
        index = self.lastAddedIndex;
    }
    
    for (NSDictionary* file in files)
    {
        [self.playlist insertObject:file atIndex:index];
        index++;
    }
    
    self.lastAddedIndex = index;
    [self invalidatePlaylistUndoHistory];
    
    [self playlistChanged];
}

- (void)clear
{
    [self stop];
    
    [musicFileManager stopBuffering];
    
    self.lastAddedIndex = -1;
    [self.playlist removeAllObjects];
    [self playlistChanged];
    
    self.currentIndex = -1;
    
    [self updateUI];
}

#pragma mark - Play

- (void)play
{
    self.pausedIntentionally = FALSE;
    
    [self.player play];
}

- (void)playAtIndex:(long)index
{
    [self playAtIndex:index atPosition:0];
}

- (void)playAtIndex:(long)index atPosition:(NSTimeInterval)position
{
    [self setIndex:index position:position];
    [self play];
}

- (void)setIndex:(long)index position:(NSTimeInterval)position
{
    [self setIndex:index position:position invalidatingPlaylistUndoHistory:YES];
}

- (void)setIndex:(long)index position:(NSTimeInterval)position invalidatingPlaylistUndoHistory:(BOOL)invalidatePlaylistUndoHistory
{
    if (invalidatePlaylistUndoHistory)
    {
        [self invalidatePlaylistUndoHistory];
    }
    
    [self stop];
    
    self.currentIndex = index;
    NSDictionary* item = [self.playlist objectAtIndex:self.currentIndex];
    
    NSString* path = [musicFileManager playPath:item];
    if (path)
    {
        NSURL* url = [NSURL fileURLWithPath:path];
        self.player = [[[AVAudioPlayer alloc] initWithContentsOfURL:url fileTypeHint:AVFileTypeMPEGLayer3 error:nil] autorelease];
        self.player.delegate = self;
        if (position)
        {
            self.player.currentTime = position;
        }
        
        self.nowPlayingInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                               [item objectForKey:@"artist"], MPMediaItemPropertyArtist,
                               [item objectForKey:@"album"], MPMediaItemPropertyAlbumTitle,
                               [item objectForKey:@"title"], MPMediaItemPropertyTitle,
                               nil];
        [self updateCover];
        [self updatedNowPlayingInfo];
        
        [musicFileManager notifyItemPlay:item];
        
        self.playerStartedAt = [NSDate date];
        self.skipScrobblingCurrent = false;
        [scrobbler sendNowPlaying:item];
    }
    
    [self.tableView reloadData];
    if (self.lastTimeTableTouchedAt == nil ||
        [[NSDate date] timeIntervalSinceDate:self.lastTimeTableTouchedAt] >= 300)
    {
        NSIndexPath* indexPath = [self indexPathForIndex:self.currentIndex];
        if (indexPath)
        {
            [self.tableView scrollToRowAtIndexPath:indexPath
                                  atScrollPosition:UITableViewScrollPositionMiddle
                                          animated:TRUE];
        }
    }
    
    [self bufferMostNecessary];
    [musicFileManager loadCover:item];
}

#pragma mark - Stop

- (void)stop
{
    if (self.player)
    {
        if (self.player.playing)
        {
            [self scrobbleIfNecessary];
        }
        
        [self.player stop];
        
        self.player = nil;
        
        [self updateUI];
    }
}

- (void)pause
{
    self.pausedIntentionally = TRUE;

    [self saveState];
    [self.player pause];
}

- (IBAction)handlePlayPauseButtonTouchDown:(id)sender
{
    if (self.player)
    {
        if (self.player.playing)
        {
            [self pause];
        }
        else
        {
            [self play];
        }
    }
    else
    {
        if ([self.playlist count] > 0)
        {
            [self playAtIndex:0];
        }
    }
    
    [self updateUI];
}

#pragma mark - Prev/Next

- (void)playNextTrack:(BOOL)respectRepeatTrack
{
    [self scrobbleIfNecessary];
    
    if (respectRepeatTrack && self.repeat == RepeatTrack)
    {
    }
    else
    {
        self.currentIndex++;
        if (self.currentIndex >= [self.playlist count])
        {
            if (self.repeat == RepeatPlaylist)
            {
                self.currentIndex = 0;
            }
            else
            {
                self.currentIndex = -1;
                self.player = nil;
                
                [self.tableView reloadData];
                [self updateUI];
                
                [self bufferMostNecessary];
                
                return;
            }
        }
    }
    
    [self playAtIndex:self.currentIndex];
}

- (void)playPrevTrack:(BOOL)respectRepeatTrack
{
    [self scrobbleIfNecessary];
    
    if (respectRepeatTrack && self.repeat == RepeatTrack)
    {
    }
    else
    {
        self.currentIndex--;
        if (self.currentIndex < 0)
        {
            if (self.repeat == RepeatPlaylist)
            {
                self.currentIndex = [self.playlist count] - 1;
            }
            else
            {
                self.currentIndex = -1;
                self.player = nil;
                
                [self.tableView reloadData];
                [self updateUI];
                
                [self bufferMostNecessary];
                
                return;
            }
        }
    }
    
    [self playAtIndex:self.currentIndex];
}

#pragma mark - Seeking

- (void)handleSeeking:(UIEventSubtype)event
{
    switch (event)
    {
        case UIEventSubtypeRemoteControlBeginSeekingBackward:
            [self.player setEnableRate:YES];
            [self.player setRate:-10.0];
            break;
            
        case UIEventSubtypeRemoteControlBeginSeekingForward:
            [self.player setEnableRate:YES];
            [self.player setRate:10.0];
            break;
            
        case UIEventSubtypeRemoteControlEndSeekingBackward:
        case UIEventSubtypeRemoteControlEndSeekingForward:
            [self.player setEnableRate:NO];
            [self.player setRate:1.0];
            break;
            
        default:
            break;
    }
}
- (IBAction)handlePositionSliderTouchUpInside:(id)sender
{
    self.player.currentTime = self.positionSlider.value;
    [self updateUI];
}

#pragma mark - Repeat

- (IBAction)handleRepeatButtonTouchDown:(id)sender
{
    self.repeat = (self.repeat + 1) % 3;
    [self updateUI];
}

#pragma mark - UI

- (void)updateUI
{
    if (self.player)
    {
        if (self.player.playing)
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"PauseActive"] forState:UIControlStateNormal];
        }
        else
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"PlayActive"] forState:UIControlStateNormal];
        }
        
        self.elapsedLabel.text = [NSString stringWithFormat:@"%02d:%02d", (int)self.player.currentTime / 60, (int)self.player.currentTime % 60];
        self.totalLabel.text = [NSString stringWithFormat:@"%02d:%02d", (int)self.player.duration / 60, (int)self.player.duration % 60];
        
        if (!self.positionSlider.tracking)
        {
            self.positionSlider.value = self.player.currentTime;
            self.positionSlider.maximumValue = self.player.duration;
            self.positionSlider.enabled = true;
        }
        
        [self.nowPlayingInfo
         setObject:[NSNumber numberWithDouble:self.player.currentTime]
         forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [self.nowPlayingInfo
         setObject:[NSNumber numberWithDouble:self.player.duration]
         forKey:MPMediaItemPropertyPlaybackDuration];
        [self updatedNowPlayingInfo];
    }
    else
    {
        if ([self.playlist count] > 0)
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"PlayActive"] forState:UIControlStateNormal];
        }
        else
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"PlayInactive"] forState:UIControlStateNormal];
        }
        
        self.elapsedLabel.text = @"00:00";
        self.totalLabel.text = @"00:00";
        
        self.positionSlider.value = 0;
        self.positionSlider.maximumValue = 0;
        self.positionSlider.enabled = false;
        
        self.nowPlayingInfo = nil;
        [self updatedNowPlayingInfo];
    }
    
    if (self.repeat == RepeatDisabled)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"RepeatDisabled"] forState:UIControlStateNormal];
    }
    if (self.repeat == RepeatPlaylist)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"RepeatPlaylist"] forState:UIControlStateNormal];
    }
    if (self.repeat == RepeatTrack)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"RepeatTrack"] forState:UIControlStateNormal];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"statisticsChanged" object:self];
}

#pragma mark - Playlist gestures

- (IBAction)handlePlaylistLeftSwipe:(UISwipeGestureRecognizer*)recognizer
{
    self.lastTimeTableTouchedAt = [NSDate date];
    
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        [self storePlaylistUndoHistory];
        
        long index = [self itemIndexForIndexPath:indexPath];
        if (index == self.currentIndex)
        {
            [self stop];
            if (self.currentIndex + 1 < [self.playlist count])
            {
                [self playAtIndex:self.currentIndex + 1];
                self.currentIndex--;
            }
        }
        else if (index < self.currentIndex)
        {
            self.currentIndex--;
        }
        self.lastAddedIndex = -1;
        [self.playlist removeObjectAtIndex:index];
        [self playlistChanged];
    }
}

- (IBAction)handlePlaylistLeftDoubleSwipe:(UISwipeGestureRecognizer*)recognizer
{
    self.lastTimeTableTouchedAt = [NSDate date];
    
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        [self storePlaylistUndoHistory];
        
        NSDictionary* section = [self.sections objectAtIndex:indexPath.section];
        NSArray* files = [section objectForKey:@"files"];
        long firstFile = [[files firstObject] longValue];
        long lastFile = [[files lastObject] longValue];
        if (firstFile <= self.currentIndex && self.currentIndex <= lastFile)
        {
            for (NSNumber* nsi in [section objectForKey:@"files"])
            {
                if ([nsi longValue] == self.currentIndex)
                {
                    [self stop];
                    if (indexPath.section + 1 < [self.sections count])
                    {
                        [self playAtIndex:[[[[self.sections objectAtIndex:indexPath.section + 1]
                                             objectForKey:@"files"]
                                            objectAtIndex:0]
                                           longValue]];
                        self.currentIndex -= [files count];
                    }
                }
            }
        }
        else if (firstFile < self.currentIndex)
        {
            self.currentIndex -= [files count];
        }
        self.lastAddedIndex = -1;
        [self.playlist removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(firstFile, lastFile - firstFile + 1)]];
        [self playlistChanged];
    }
}

#pragma mark - Playlist actions

- (IBAction)handlePinch:(UIPinchGestureRecognizer*)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateEnded)
    {
        return;
    }
    
    UIActionSheet* actionSheet = [[UIActionSheet alloc] initWithTitle:@"Current playlist"
                                                             delegate:self
                                                    cancelButtonTitle:nil
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:nil];
    NSMutableArray* buttons = [NSMutableArray array];
    
    if ([self.playlistUndoHistory count] > 0)
    {
        [actionSheet addButtonWithTitle:NSLocalizedString(@"Undo", nil)];
        [buttons addObject:@"Undo"];
    }
    
    [buttons addObject:@"Clear"];
    actionSheet.destructiveButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Clear", nil)];
    
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    
    objc_setAssociatedObject(actionSheet, ACTIONSHEET, @"Current playlist", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(actionSheet, BUTTONS, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [actionSheet showInView:[self.view window]];
    [actionSheet release];
}

- (void)handlePlaylistAction:(NSString*)action
{
    if ([action isEqualToString:@"Undo"])
    {
        [self undoLastAction];
    }
    
    if ([action isEqualToString:@"Clear"])
    {
        [self storePlaylistUndoHistory];
        [self clear];
    }
}

#pragma mark - Toolbar

- (IBAction)handleToolbarSwipeUp:(UISwipeGestureRecognizer*)recognizer
{
    if (!self.toolbarOpen)
    {
        self.toolbarOpen = YES;
        [self.view removeConstraint:self.hideToolbarConstraint];
        [UIView animateWithDuration:0.5f animations:^{
            [self.view layoutSubviews];
        }];
    }
}

- (IBAction)handleToolbarSwipeDown:(UISwipeGestureRecognizer*)recognizer
{
    [self closeToolbar];
}

- (void)closeToolbar
{
    if (self.toolbarOpen)
    {
        self.toolbarOpen = NO;
        [self.view addConstraint:self.hideToolbarConstraint];
        [UIView animateWithDuration:0.5f animations:^{
            [self.view layoutSubviews];
        }];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[[self.sections objectAtIndex:section] objectForKey:@"files"] count];
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    return [[self.sections objectAtIndex:section] objectForKey:@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString* cellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil)
    {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
    }
    
    NSDictionary* item = [self itemForIndexPath:indexPath];
    
    cell.textLabel.text = [item objectForKey:@"name"];
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.lastTimeTableTouchedAt = [NSDate date];
    
    [self storePlaylistUndoHistory];
    [self setIndex:[self itemIndexForIndexPath:indexPath] position:0 invalidatingPlaylistUndoHistory:NO];
    [self play];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell.backgroundColor = [UIColor clearColor];
    cell.backgroundView = nil;
    cell.textLabel.textColor = [UIColor blackColor];
    
    NSDictionary* item = [self itemForIndexPath:indexPath];
    
    MusicFileState state = [musicFileManager state:item];
    if (state.state == MusicFileNotBuffered)
    {
        cell.textLabel.textColor = [UIColor grayColor];
    }
    if (state.state == MusicFileBuffering)
    {
        [self setBufferingCell:cell backgroundViewForState:state];
    }
    if (state.state == MusicFileBuffered)
    {
    }
    
    if ([self itemIndexForIndexPath:indexPath] == self.currentIndex)
    {
        cell.textLabel.textColor = [UIColor orangeColor];
    }
}

- (void)setBufferingCell:(UITableViewCell*)cell backgroundViewForState:(MusicFileState)state
{    
    UIColor* fillColor = [UIColor grayColor];
    if (state.buffering.isError)
    {
        fillColor = [UIColor redColor];
    }
    
    UIView* view = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    CAGradientLayer* gradient = [CAGradientLayer layer];
    gradient.frame = view.bounds;
    gradient.colors = [NSArray arrayWithObjects:(id)[[UIColor whiteColor] CGColor], [fillColor CGColor], nil];
    gradient.locations = [NSArray arrayWithObjects:[NSNumber numberWithFloat:state.buffering.progress], (id)[NSNumber numberWithFloat:state.buffering.progress], nil];
    gradient.startPoint = CGPointMake(0.0, 0.5);
    gradient.endPoint = CGPointMake(1.0, 0.5);
    [view.layer insertSublayer:gradient atIndex:0];
    cell.backgroundView = view;
    [view release];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.lastTimeTableTouchedAt = [NSDate date];
}

#pragma mark - AVAudioPlayer delegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    MusicFileState state = [musicFileManager state:[self.playlist objectAtIndex:self.currentIndex]];
    if (state.state == MusicFileBuffering)
    {
        [self tryToResumePlayingNowBufferingFile];
        return;
    }
    
    [self playNextTrack:TRUE];
    [self saveState];
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
    [self pause];
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player withOptions:(NSUInteger)flags
{
    [self.player prepareToPlay];
    [self play];
}

- (void)onAudioRouteChange:(NSNotification*)notification
{
    NSInteger reason = [[[notification userInfo] objectForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
    {
        [self pause];
    }
}

#pragma mark - GCDAsyncSocket delegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{    
	[newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:10 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSData *strData = [data subdataWithRange:NSMakeRange(0, [data length] - 2)];
    NSString *command = [[[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding] autorelease];
    
    if ([command isEqualToString:@"become_superseeded"])
    {
        NSMutableDictionary* result = [NSMutableDictionary dictionary];
        if (self.player && self.player.playing)
        {
            NSMutableArray* list = [NSMutableArray arrayWithCapacity:self.playlist.count];
            for (int i = 0; i < self.playlist.count; i++)
            {
                [list setObject:[[self.playlist objectAtIndex:i] objectForKey:@"url"] atIndexedSubscript:i];
            }
            [result setObject:list forKey:@"playlist"];
            
            NSMutableDictionary* current = [NSMutableDictionary dictionary];
            [current setObject:[NSNumber numberWithLong:(self.currentIndex)] forKey:@"index"];
            [current setObject:[NSNumber numberWithDouble:(self.player.currentTime)] forKey:@"position"];
            [result setObject:current forKey:@"current"];
        }
        
        [sock writeData:[[NSJSONSerialization dataWithJSONObject:result
                                                         options:0
                                                           error:nil] copy]
            withTimeout:10
                    tag:0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pause];
        });
    }
    else
    {
        [sock disconnect];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
	[sock disconnect];
}

#pragma mark - Action sheet delegate

- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString* sheet = objc_getAssociatedObject(actionSheet, ACTIONSHEET);
    
    NSArray* buttons = objc_getAssociatedObject(actionSheet, BUTTONS);
    if (buttonIndex >= [buttons count])
    {
        return;
    }
    
    NSObject* button = [buttons objectAtIndex:buttonIndex];
    
    if ([sheet isEqualToString:@"Current playlist"])
    {
        [self handlePlaylistAction:(NSString*)button];
    }
    
    if ([sheet isEqualToString:@"Recommendations"])
    {
        [self handleRecommendationsAction:(NSDictionary*)button];
    }
}

#pragma mark - Alert view delegate

- (void)alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    NSString* view = objc_getAssociatedObject(alertView, ALERTVIEW);
    
    if ([view isEqualToString:@"SUPERSEED"])
    {
        [self handleSuperseedAlertView:alertView buttonIndex:buttonIndex];
    }
}

#pragma mark - Internals

- (void)playlistChanged
{
    [self.sections removeAllObjects];

    for (long i = 0; i < [self.playlist count]; i++)
    {
        NSDictionary* file = [self.playlist objectAtIndex:i];
        
        NSMutableString* album = [[[NSMutableString alloc] init] autorelease];
        if (!([[file objectForKey:@"album"] isEqualToString:@""]))
        {
            [album appendString:[file objectForKey:@"album"]];
            if (!([[file objectForKey:@"date"] isEqualToString:@""]))
            {
                [album appendString:[NSString stringWithFormat:@" (%@)", [file objectForKey:@"date"]]];
            }
        }
        
        NSMutableString* title = [[album mutableCopy] autorelease];
        if (!([[file objectForKey:@"artist"] isEqualToString:@""]))
        {
            if (!([title isEqualToString:@""]))
            {
                [title appendString:@" by "];
            }
            [title appendString:[file objectForKey:@"artist"]];
        }
        
        if (
            [self.sections count] == 0 ||
            ![title isEqualToString:[[self.sections lastObject] objectForKey:@"title"]] ||
            [[file objectForKey:@"track"] integerValue] <
                [[[self.playlist objectAtIndex:(i - 1)] objectForKey:@"track"] integerValue]
        )
        {
            if (
                [self.sections count] > 0 &&
                ![album isEqualToString:@""] &&
                [album isEqualToString:[[self.sections lastObject] objectForKey:@"album"]] &&
                [[file objectForKey:@"track"] integerValue] >=
                    [[[self.playlist objectAtIndex:(i - 1)] objectForKey:@"track"] integerValue]
            )
            {
                [[self.sections lastObject] setObject:album forKey:@"title"];
            }
            else
            {
                [self.sections addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:title, @"title", album, @"album", [NSMutableArray array], @"files", nil]];
            }
        }
        
        [[[self.sections lastObject] objectForKey:@"files"] addObject:[NSNumber numberWithLong:i]];
    }
    
    [self.tableView reloadData];
    
    [self bufferMostNecessary];
    [self saveState];
}

#pragma mark - State

- (void)saveState
{
    @synchronized([NSUserDefaults standardUserDefaults])
    {
        NSDictionary* current = [NSDictionary dictionaryWithObjectsAndKeys:
                                 self.playlist, @"playlist",
                                 [NSNumber numberWithLong:self.currentIndex], @"index",
                                 [NSNumber numberWithDouble:self.player.currentTime], @"position",
                                 [NSNumber numberWithInt:self.repeat], @"repeat",
                                 nil];
        [[NSUserDefaults standardUserDefaults] setObject:current forKey:@"current"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

#pragma mark - Buffering

- (void)bufferMostNecessary
{
    if (self.bufferMostNecessaryOverride != -1)
    {
        [musicFileManager buffer:[self.playlist objectAtIndex:self.bufferMostNecessaryOverride]];
        self.bufferMostNecessaryOverride = -1;
        return;
    }
    
    if (self.currentIndex != -1)
    {
        for (long i = self.currentIndex; i < [self.playlist count]; i++)
        {
            NSDictionary* item = [self.playlist objectAtIndex:i];
            MusicFileState state = [musicFileManager state:item];
            if (state.state != MusicFileBuffered)
            {
                [musicFileManager buffer:item];
                return;
            }
        }
    }
    
    for (NSDictionary* item in self.playlist)
    {
        MusicFileState state = [musicFileManager state:item];
        if (state.state != MusicFileBuffered)
        {
            [musicFileManager buffer:item];
            return;
        }
    }
    
    [musicFileManager stopBuffering];
}

- (void)tryToResumePlayingNowBufferingFile
{
    if (self.currentIndex == -1)
    {
        return;
    }
    
    if (self.player.playing)
    {
        return;
    }
    
    if (self.pausedIntentionally)
    {
        return;
    }
    
    MusicFileState state = [musicFileManager state:[self.playlist objectAtIndex:self.currentIndex]];
    if (state.state == MusicFileBuffering)
    {
        [self playAtIndex:self.currentIndex atPosition:self.player.duration];
    }
}

#pragma mark - Addressing

- (long)itemIndexForIndexPath:(NSIndexPath*)indexPath
{
    return [[[[self.sections objectAtIndex:indexPath.section] objectForKey:@"files"] objectAtIndex:indexPath.row] longValue];
}

- (NSDictionary*)itemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.playlist objectAtIndex:[self itemIndexForIndexPath:indexPath]];
}

- (NSIndexPath*)indexPathForIndex:(long)index
{
    long row, section;
    for (section = 0; section < [self.sections count]; section++)
    {
        NSArray* sectionFiles = [[self.sections objectAtIndex:section] objectForKey:@"files"];
        for (row = 0; row < [sectionFiles count]; row++)
        {
            if ([[sectionFiles objectAtIndex:row] longValue] == self.currentIndex)
            {
                return [NSIndexPath indexPathForRow:row inSection:section];
            }
        }
    }
    
    return nil;
}

#pragma mark - MusicFileManager delegate

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
    
    [self tryToResumePlayingNowBufferingFile];
}

- (void)onMusicFileManagerBufferingProgress:(NSNotification*)notification
{
    if (self.bufferingProgressReportedAt && [[NSDate date] timeIntervalSinceDate:self.bufferingProgressReportedAt] < 2.0)
    {
        return;
    }
    self.bufferingProgressReportedAt = [NSDate date];
        
    for (int section = 0; section < [self.sections count]; section++)
    {
        NSArray* fileIndexes = [[self.sections objectAtIndex:section] objectForKey:@"files"];
        for (int row = 0; row < [fileIndexes count]; row++)
        {
            NSDictionary* playlistItem = [self.playlist objectAtIndex:[[fileIndexes objectAtIndex:row] intValue]];
            if ([[playlistItem objectForKey:@"path"] isEqualToString:[[[notification userInfo] objectForKey:@"file"] objectForKey:@"path"]])
            {
                UITableViewCell* cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                if (cell)
                {
                    [self setBufferingCell:cell backgroundViewForState:[musicFileManager state:playlistItem]];
                }
            }
        }
    }
    
    [self tryToResumePlayingNowBufferingFile];
}

- (void)onMusicFileManagerBufferingCompleted
{
    if (self.whenItemIsBufferedPlayAtIndex != -1 && self.whenItemIsBufferedPlayAtPosition != -1)
    {
        bool oldSkipScrobblingCurrent = self.skipScrobblingCurrent;
        [self playAtIndex:self.whenItemIsBufferedPlayAtIndex atPosition:self.whenItemIsBufferedPlayAtPosition];
        self.whenItemIsBufferedPlayAtIndex = -1;
        self.whenItemIsBufferedPlayAtPosition = -1;
        self.skipScrobblingCurrent = oldSkipScrobblingCurrent;
    }
    
    [self bufferMostNecessary];
}

#pragma mark - Scrobbling

- (void)handleLoveButtonTouchDown:(id)sender
{
    if (self.currentIndex != -1)
    {
        NSDictionary* item = [self.playlist objectAtIndex:self.currentIndex];
        [scrobbler love:item];
        [self closeToolbar];
    }
}

- (void)handleScrobblerButtonTouchDown:(id)sender
{
    scrobbler.enabled = !scrobbler.enabled;
    [self showScrobblerEnabled];
}

- (void)scrobbleIfNecessary
{
    if (self.currentIndex == -1)
    {
        return;
    }
    
    if (self.skipScrobblingCurrent)
    {
        self.skipScrobblingCurrent = false;
        return;
    }
    
    if ([[NSDate date] timeIntervalSinceDate:self.playerStartedAt] >= MIN(self.player.duration / 2, 240))
    {
        [scrobbler scrobble:[self.playlist objectAtIndex:self.currentIndex] startedAt:self.playerStartedAt];
    }
}

- (void)showScrobblerEnabled
{
    if (scrobbler.enabled)
    {
        self.scrobblerButton.alpha = 1.0;
        self.scrobblerLabel.alpha = 1.0;
        self.scrobblerLabel.text = @"Enabled";
    }
    else
    {
        self.scrobblerButton.alpha = 0.2;
        self.scrobblerLabel.alpha = 0.2;
        self.scrobblerLabel.text = @"Disabled";
    }
}

- (void)onScrobblerQueueChanged
{
    int count = [scrobbler queueSize];
    if (count > 0)
    {
        self.scrobblerBadge.value = count;
        if ([self.scrobblerBadge superview] == NULL)
        {
            [self.scrobblerButton addSubview:self.scrobblerBadge];
        }
    }
    else
    {
        if ([self.scrobblerBadge superview] != NULL)
        {
            [self.scrobblerBadge removeFromSuperview];
        }
    }
}

#pragma mark - Cover

- (void)updateCover
{
    if (self.currentIndex != -1 && self.nowPlayingInfo)
    {
        NSString* coverPath = [musicFileManager coverPath:[self.playlist objectAtIndex:self.currentIndex]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath])
        {
            UIImage* image = [UIImage imageWithContentsOfFile:coverPath];
            if (image)
            {
                MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc] initWithImage:image];
                if (artwork)
                {
                    [self.nowPlayingInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];
                    [self updatedNowPlayingInfo];
                }
            }
        }
    }
}

- (void)updatedNowPlayingInfo
{
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = self.nowPlayingInfo;
}

#pragma mark - Lyrics

- (void)handleGoogleButtonTouchDown:(id)sender
{
    if (self.currentIndex != -1)
    {
        NSDictionary* item = [self.playlist objectAtIndex:self.currentIndex];
        ASIFormDataRequest* asiRequest = [[ASIFormDataRequest alloc] init];
        [asiRequest setStringEncoding:NSUTF8StringEncoding];
        NSURL* url = [NSURL URLWithString:
                      [NSString stringWithFormat:@"%@/lyrics/%@/%@",
                       [[item objectForKey:@"player"] objectForKey:@"url"],
                       [asiRequest encodeURL:[item objectForKey:@"artist"]],
                       [asiRequest encodeURL:[item objectForKey:@"title"]]]];
        [asiRequest release];
        [[UIApplication sharedApplication] openURL:url];
        [self closeToolbar];
    }
}

#pragma mark - Superseeding

- (void)handleSuperseedButtonTouchDown:(id)sender
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError* error;
        NSURL* url = [NSURL URLWithString:[[[players objectAtIndex:0] objectForKey:@"url"]
                                           stringByAppendingString:@"/player/become_superseeded"]];
        ASIFormDataRequest* request = [ASIFormDataRequest requestWithURL:url];
        [request startSynchronous];
        if ([request error] || [request responseStatusCode] != 200)
        {
            NSString* errorDescription;
            if ([request error])
            {
                errorDescription = [[request error] localizedDescription];
            }
            else
            {
                errorDescription = [request responseStatusMessage];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Superseeding error", nil)
                                                                message:errorDescription
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                      otherButtonTitles:nil];
                [alert show];
            });
        }
        else
        {
            NSDictionary* data = [NSJSONSerialization
                                  JSONObjectWithData:[request responseData]
                                  options:0
                                  error:&error];
            if (!data)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertView* alert = [[UIAlertView alloc]
                                          initWithTitle:[error localizedDescription]
                                          message:[error localizedFailureReason]
                                          delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                          otherButtonTitles:nil];
                    [alert show];
                });
                return;
            }
            [self replacePlaylistWithData:data updateIfNecessary:YES];
        }
    });
    [self closeToolbar];
}

- (void)replacePlaylistWithData:(NSDictionary*)data updateIfNecessary:(BOOL)updateIfNecessary
{
    NSDictionary* player = [players objectAtIndex:0];
    NSArray* dataPlaylist = [data objectForKey:@"playlist"];
    
    NSMutableArray* items = [NSMutableArray array];
    int position = 0;
    for (int i = 0; i < dataPlaylist.count; i++)
    {
        NSString* directory = [[dataPlaylist objectAtIndex:i] stringByDeletingLastPathComponent];
        NSString* file = [[dataPlaylist objectAtIndex:i] lastPathComponent];
        
        NSDictionary* index = [musicTableService loadRawIndexForPlayer:player directory:directory];
        NSDictionary* item = [index objectForKey:file];
        if (item == NULL)
        {
            if (updateIfNecessary)
            {
                [controllers.tabBar setSelectedViewController:controllers.library];
                [controllers.library updateLibraryWithSuccessCallback:^{
                    [controllers.tabBar setSelectedViewController:controllers.current];
                    [self replacePlaylistWithData:data updateIfNecessary:FALSE];
                }];
                return;
            }
        }
        else
        {
            NSMutableDictionary* itemWithPlayer = [[item mutableCopy] autorelease];
            itemWithPlayer[@"player"] = player;
            [items addObject:itemWithPlayer];
            if (i < [[data objectForKey:@"position"] intValue])
            {
                position++;
            }
        }
    }
    
    int unbufferedItems = 0;
    for (int i = 0; i < items.count; i++)
    {
        if ([musicFileManager state:[items objectAtIndex:i]].state != MusicFileBuffered)
        {
            unbufferedItems++;
        }
    }
    if (unbufferedItems > 20)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Question", nil)
                                                         message:[NSString stringWithFormat:NSLocalizedString(@"There are %d unbuffered items in your MPD playlist. What should I add?", nil), unbufferedItems]
                                                        delegate:self
                                               cancelButtonTitle:NSLocalizedString(@"Entire playlist", nil)
                                               otherButtonTitles:NSLocalizedString(@"Current album and everything after", nil), NSLocalizedString(@"Only current album", nil), nil];
            objc_setAssociatedObject(alert, ALERTVIEW, @"SUPERSEED", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(alert, DATA, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(alert, ITEMS, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(alert, POSITION, [NSNumber numberWithInteger:position], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [alert show];
            [alert release];
        });
        return;
    }
    else
    {
        [self replacePlaylistWithData:data items:items atIndex:position];
    }
}

- (void)replacePlaylistWithData:(NSDictionary*)data items:(NSArray*)items atIndex:(int)index
{
    if (items.count)
    {
        [self storePlaylistUndoHistory];
        [self clear];
        
        if ([musicFileManager state:[items objectAtIndex:index]].state == MusicFileBuffered)
        {
            [self addFiles:items mode:AddToTheEnd];
            [self playAtIndex:index atPosition:[[data objectForKey:@"elapsed"] intValue]];
        }
        else
        {
            self.bufferMostNecessaryOverride = index;
            [self addFiles:items mode:AddToTheEnd];
            self.whenItemIsBufferedPlayAtIndex = index;
            self.whenItemIsBufferedPlayAtPosition = [[data objectForKey:@"elapsed"] intValue];
        }
        self.skipScrobblingCurrent = [[data objectForKey:@"scrobbled"] boolValue];
    }
}

- (void)handleSuperseedAlertView:(UIAlertView*)alertView buttonIndex:(NSInteger)buttonIndex
{
    NSDictionary* data = objc_getAssociatedObject(alertView, DATA);
    NSArray* items = objc_getAssociatedObject(alertView, ITEMS);
    int position = [objc_getAssociatedObject(alertView, POSITION) intValue];
    if (buttonIndex == 1 || buttonIndex == 2)
    {
        int currentAlbumBeginning;
        NSString* currentAlbum = [[items objectAtIndex:position] objectForKey:@"album"];
        for (currentAlbumBeginning = position; currentAlbumBeginning > 0; currentAlbumBeginning--)
        {
            if (![[[items objectAtIndex:(currentAlbumBeginning - 1)] objectForKey:@"album"] isEqualToString:currentAlbum])
            {
                break;
            }
        }
        items = [items subarrayWithRange:NSMakeRange(currentAlbumBeginning, items.count - currentAlbumBeginning)];
        position -= currentAlbumBeginning;
        
        if (buttonIndex == 2)
        {
            int currentAlbumEnd;
            for (currentAlbumEnd = position; currentAlbumEnd < items.count - 1; currentAlbumEnd++)
            {
                if (![[[items objectAtIndex:(currentAlbumEnd + 1)] objectForKey:@"album"] isEqualToString:currentAlbum])
                {
                    break;
                }
            }
            currentAlbumEnd++;
            items = [items subarrayWithRange:NSMakeRange(0, currentAlbumEnd)];
        }
    }
    [self replacePlaylistWithData:data items:items atIndex:position];
}

#pragma mark - Recommendations

- (IBAction)handleRecommendationsButtonTouchDown:(id)sender
{
    UIActionSheet* actionSheet = [[UIActionSheet alloc] initWithTitle:@"Recommendations"
                                                             delegate:self
                                                    cancelButtonTitle:nil
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:nil];
    NSMutableArray* buttons = [NSMutableArray array];
    
    
    ASIFormDataRequest* asiRequest = [[ASIFormDataRequest alloc] init];
    [asiRequest setStringEncoding:NSUTF8StringEncoding];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"New unheard albums", nil)];
    [buttons addObject:@{@"class": @"ShowURL",
                         @"player": [players objectAtIndex:0],
                         @"title": @"New unheard albums",
                         @"url": [NSString stringWithFormat:@"%@/recommendations/unheard/%@?sort=recent&limit=100",
                                  [[players objectAtIndex:0] objectForKey:@"url"],
                                  [asiRequest encodeURL:lastFmUsername]]}];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Old unheard albums", nil)];
    [buttons addObject:@{@"class": @"ShowURL",
                         @"player": [players objectAtIndex:0],
                         @"title": @"Old unheard albums",
                         @"url": [NSString stringWithFormat:@"%@/recommendations/unheard/%@?sort=random&limit=100",
                                  [[players objectAtIndex:0] objectForKey:@"url"],
                                  [asiRequest encodeURL:lastFmUsername]]}];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Friends", nil)];
    [buttons addObject:@{@"class": @"ShowRecommendationsForFromController"}];
    
    [asiRequest release];
    
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    
    objc_setAssociatedObject(actionSheet, ACTIONSHEET, @"Recommendations", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(actionSheet, BUTTONS, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [actionSheet showInView:[self.view window]];
    [actionSheet release];
    
    [self closeToolbar];
}

- (void)handleRecommendationsAction:(NSDictionary*)action
{
    [self performRecommendationsAction:action];
}

- (void)performRecommendationsAction:(NSDictionary*)action
{
    if ([[action objectForKey:@"class"] isEqualToString:@"ShowURL"])
    {
        [recommendationsUtils
         processRecommendationsUrl:[NSURL URLWithString:[action objectForKey:@"url"]]
         withPlayer:[action objectForKey:@"player"]
         title:[action objectForKey:@"title"]
         action:RecommendationsShowInController];
    }
        
    if ([[action objectForKey:@"class"] isEqualToString:@"ShowRecommendationsForFromController"])
    {
        RecommendationsForFromController* recommendations = [[RecommendationsForFromController alloc] init];
        UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:recommendations];
        [self presentViewController:navigation animated:YES completion:^{
        }];
        [recommendations release];
    }
}

#pragma mark - Undo

- (void)storePlaylistUndoHistory
{
    [self.playlistUndoHistory addObject:
     [NSDictionary dictionaryWithObjectsAndKeys:[NSMutableArray arrayWithArray:self.playlist], @"playlist",
      [NSNumber numberWithLong:self.currentIndex], @"index",
      [NSNumber numberWithDouble:self.player.currentTime], @"position",
      [NSNumber numberWithBool:self.player.playing], @"playing",
      nil]];
    
    if ([self.playlistUndoHistory count] > 10)
    {
        [self.playlistUndoHistory removeObjectAtIndex:0];
    }
}

- (void)invalidatePlaylistUndoHistory
{
    self.playlistUndoHistory = [NSMutableArray array];
}

- (void)undoLastAction
{
    if ([self.playlistUndoHistory count] > 0)
    {
        NSDictionary* undo = [self.playlistUndoHistory lastObject];
        
        NSMutableArray* undoPlaylist = [undo objectForKey:@"playlist"];
        long undoIndex = [[undo objectForKey:@"index"] intValue];
        double undoPosition = [[undo objectForKey:@"position"] doubleValue];
        bool undoWasPlaying = [[undo objectForKey:@"playing"] boolValue];
        
        bool currentItemIsEqualToUndoItem = NO;
        if (self.currentIndex != -1 &&
            undoIndex != -1 &&
            [[[self.playlist objectAtIndex:self.currentIndex] objectForKey:@"path"] isEqualToString:
             [[undoPlaylist objectAtIndex:undoIndex] objectForKey:@"path"]])
        {
            currentItemIsEqualToUndoItem = YES;
        }
        
        self.playlist = undoPlaylist;
        [self playlistChanged];
        
        [self.playlistUndoHistory removeLastObject];
        
        if (currentItemIsEqualToUndoItem)
        {
            self.currentIndex = undoIndex;
        }
        else
        {
            if (undoIndex != -1)
            {
                [self setIndex:undoIndex position:undoPosition invalidatingPlaylistUndoHistory:NO];
                if (undoWasPlaying)
                {
                    [self play];
                }
            }
            else
            {
                self.currentIndex = -1;
                [self.tableView reloadData];
            }
        }
    }
}

#pragma mark - Statistics

- (NSArray*)getStatistics
{
    int playlistDuration = 0;
    for (int i = 0; i < [self.playlist count]; i++)
    {
        if (self.currentIndex > -1)
        {
            if (i < self.currentIndex)
            {
                continue;
            }
            else if (i == self.currentIndex)
            {
                if (self.player)
                {
                    playlistDuration -= self.player.currentTime;
                }
            }
        }
        
        NSObject* duration = [[self.playlist objectAtIndex:i] objectForKey:@"duration"];
        if (duration != nil && ![duration isKindOfClass:[NSNull class]])
        {
            playlistDuration += [(NSNumber*)duration intValue];
        }
    }
    
    if (playlistDuration > 0)
    {
        NSString* durationInfo = [NSString stringWithFormat:@"You have %dh %dm of music, ",
                                  playlistDuration / 3600, playlistDuration / 60 % 60];
        
        if (!self.player.playing)
        {
            durationInfo = [durationInfo stringByAppendingString:@"if you turn it on now, "];
        }
        
        NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
        if (playlistDuration < 86400)
        {
            dateFormatter.dateStyle = NSDateFormatterNoStyle;
        }
        else
        {
            dateFormatter.dateStyle = NSDateIntervalFormatterShortStyle;
        }
        dateFormatter.timeStyle = NSDateFormatterShortStyle;
        NSDate* end = [NSDate dateWithTimeIntervalSinceNow:playlistDuration];
        durationInfo = [durationInfo stringByAppendingString:
                        [NSString stringWithFormat:@"it will end at %@", [dateFormatter stringFromDate:end]]];
        
        return @[durationInfo];
    }
    else
    {
        return @[@"Playlist is empty"];
    }
}

#pragma mark - System volume

- (void)onSystemVolumeChanged:(NSNotification*)notification
{
    if (self.player)
    {
        if ([[notification.userInfo objectForKey:@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"]
             isEqualToString:@"ExplicitVolumeChange"])
        {
            float volume = [[[notification userInfo]
                             objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"]
                            floatValue];
            if (volume < 0.01)
            {
                if (self.player.playing)
                {
                    [self pause];
                    
                    self.pausedByLowVolume = true;
                    [self.pausedByLowVolumeKeepAliver startWithDuration:900];
                }
            }
            else
            {
                if (self.pausedByLowVolume)
                {
                    [self play];
                    
                    self.pausedByLowVolume = false;
                    [self.pausedByLowVolumeKeepAliver stop];
                }
            }
        }
    }
}

- (void)dealloc {
    [_hideToolbarConstraint release];
    [super dealloc];
}


@end

//
//  PlaylistController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "CurrentController.h"

#import "Globals.h"

#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

#import "CocoaAsyncSocket/GCDAsyncSocket.h"
#import "JSONKit.h"
#import "MKNumberBadgeView.h"

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

@property (nonatomic)         enum { RepeatDisabled, RepeatPlaylist, RepeatTrack } repeat;

@property (nonatomic, retain) NSMutableDictionary* nowPlayingInfo;

@property (nonatomic, retain) NSTimer* periodicTimer;

@property (nonatomic, retain) NSDate* bufferingProgressReportedAt;

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
        self.tabBarItem.image = [UIImage imageNamed:@"tabbar_current.png"];
        
        self.toolbarOpen = NO;
        
        self.playlist = [[NSMutableArray alloc] init];
        self.sections = [[NSMutableArray alloc] init];
        
        self.lastAddedIndex = -1;
        self.lastTimeTableTouchedAt = nil;
        [self invalidatePlaylistUndoHistory];
        
        self.currentIndex = -1;
        self.player = nil;
        
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
            [self _playlistChanged];
            
            self.repeat = [[current objectForKey:@"repeat"] intValue];
            [self updateUI];
            
            long index = [[current objectForKey:@"index"] longValue];
            double position = [[current objectForKey:@"position"] doubleValue];
            if (index >= 0 && index < [self.playlist count])
            {
                [self initAtIndex:index atPosition:position];
            }
        }
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    CGRect tableViewRect = self.tableView.frame;
    tableViewRect.size.height = [UIScreen mainScreen].bounds.size.height - 168;
    self.tableView.frame = tableViewRect;
    
    CGRect toolbarRect = self.toolbar.frame;
    toolbarRect.size.height = 100;
    toolbarRect.origin.y = tableViewRect.size.height;
    self.toolbar.frame = toolbarRect;
    
    [self showScrobblerEnabled];
    
    self.scrobblerBadge = [[MKNumberBadgeView alloc] initWithFrame:CGRectMake(28, 0, 36, 24)];
    self.scrobblerBadge.shine = NO;
    self.scrobblerBadge.shadow = NO;
    [self onScrobblerQueueChanged];
    
    #if TARGET_IPHONE_SIMULATOR
        UISlider* volumeView = [[UISlider alloc] initWithFrame:self.volumeView.bounds];
    #else
        MPVolumeView* volumeView = [[MPVolumeView alloc] initWithFrame:self.volumeView.bounds];
    #endif
    [self.volumeView addSubview:volumeView];
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
    
    [self _playlistChanged];
}

- (void)clear
{
    [self stop];
    
    [musicFileManager stopBuffering];
    
    self.lastAddedIndex = -1;
    [self.playlist removeAllObjects];
    [self _playlistChanged];
    
    self.currentIndex = -1;
    
    [self updateUI];
}

- (void)playAtIndex:(long)index
{
    [self playAtIndex:index atPosition:0];
}

- (void)playAtIndex:(long)index atPosition:(NSTimeInterval)position
{
    [self initAtIndex:index atPosition:position];
    [self.player play];
}

- (void)initAtIndex:(long)index atPosition:(NSTimeInterval)position
{
    [self initAtIndex:index atPosition:position invalidatingPlaylistUndoHistory:YES];
}

- (void)initAtIndex:(long)index atPosition:(NSTimeInterval)position invalidatingPlaylistUndoHistory:(BOOL)invalidatePlaylistUndoHistory
{
    if (invalidatePlaylistUndoHistory)
    {
        [self invalidatePlaylistUndoHistory];
    }
    
    [self stop];
    
    self.currentIndex = index;
    NSDictionary* item = [self.playlist objectAtIndex:self.currentIndex];
    
    NSString* path = [musicFileManager getPath:item];
    if (path)
    {
        NSURL* url = [NSURL fileURLWithPath:path];
        self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url fileTypeHint:AVFileTypeMPEGLayer3 error:nil];
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
        
        [musicFileManager notifyFileUsage:item];
        
        self.playerStartedAt = [NSDate date];
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

- (void)pause
{
    [self saveState];
    [self.player pause];
}

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

- (void)periodic
{
    [self updateUI];
}

- (void)updateUI
{
    if (self.player)
    {
        if (self.player.playing)
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"pause_active.png"] forState:UIControlStateNormal];
        }
        else
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"play_active.png"] forState:UIControlStateNormal];
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
            [self.playPauseButton setImage:[UIImage imageNamed:@"play_active.png"] forState:UIControlStateNormal];
        }
        else
        {
            [self.playPauseButton setImage:[UIImage imageNamed:@"play_inactive.png"] forState:UIControlStateNormal];
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
        [self.repeatButton setImage:[UIImage imageNamed:@"repeat_disabled.png"] forState:UIControlStateNormal];
    }
    if (self.repeat == RepeatPlaylist)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"repeat_playlist.png"] forState:UIControlStateNormal];
    }
    if (self.repeat == RepeatTrack)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"repeat_track.png"] forState:UIControlStateNormal];
    }
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
            [self.player play];
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

- (IBAction)handlePositionSliderTouchUpInside:(id)sender
{
    self.player.currentTime = self.positionSlider.value;
    [self updateUI];
}

- (IBAction)handleRepeatButtonTouchDown:(id)sender
{
    self.repeat = (self.repeat + 1) % 3;
    [self updateUI];
}

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
        [self _playlistChanged];
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
        [self _playlistChanged];
    }
}

- (IBAction)handleToolbarSwipeUp:(UISwipeGestureRecognizer*)recognizer
{
    if (!self.toolbarOpen)
    {
        self.toolbarOpen = YES;
        [UIView animateWithDuration:0.5f animations:^{
            self.toolbar.frame = CGRectInset(self.toolbar.frame, 0, -80);
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
        [UIView animateWithDuration:0.5f animations:^{
            self.toolbar.frame = CGRectInset(self.toolbar.frame, 0, 80);
        }];
    }
}

- (IBAction)handlePinch:(UIPinchGestureRecognizer*)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateEnded)
    {
        return;
    }
    
    [self storePlaylistUndoHistory];
    [self clear];
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
    [self initAtIndex:[self itemIndexForIndexPath:indexPath] atPosition:0 invalidatingPlaylistUndoHistory:NO];
    [self.player play];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell.backgroundColor = [UIColor clearColor];
    cell.backgroundView = nil;
    cell.textLabel.textColor = [UIColor blackColor];
    
    NSDictionary* item = [self itemForIndexPath:indexPath];
    
    MusicFileState state = [musicFileManager getState:item];
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
    MusicFileState state = [musicFileManager getState:[self.playlist objectAtIndex:self.currentIndex]];
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
    [self.player play];
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
    NSString *command = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    
    if ([command isEqualToString:@"become_superseeded"])
    {
        NSMutableDictionary* result = [[NSMutableDictionary alloc] init];
        if (self.player && self.player.playing)
        {            
            NSMutableArray* list = [[NSMutableArray alloc] initWithCapacity:self.playlist.count];
            for (int i = 0; i < self.playlist.count; i++)
            {
                [list setObject:[[self.playlist objectAtIndex:i] objectForKey:@"url"] atIndexedSubscript:i];
            }
            [result setObject:list forKey:@"playlist"];
            
            NSMutableDictionary* current = [[NSMutableDictionary alloc] init];
            [current setObject:[NSNumber numberWithLong:(self.currentIndex)] forKey:@"index"];
            [current setObject:[NSNumber numberWithDouble:(self.player.currentTime)] forKey:@"position"];
            [result setObject:current forKey:@"current"];
        }
        
        [sock writeData:[[result JSONData] copy] withTimeout:10 tag:0];
        
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

#pragma mark - Internals

- (void)_playlistChanged
{
    [self.sections removeAllObjects];

    for (long i = 0; i < [self.playlist count]; i++)
    {
        NSDictionary* file = [self.playlist objectAtIndex:i];
        
        NSMutableString* album = [[NSMutableString alloc] init];
        if (!([[file objectForKey:@"album"] isEqualToString:@""]))
        {
            [album appendString:[file objectForKey:@"album"]];
            if (!([[file objectForKey:@"date"] isEqualToString:@""]))
            {
                [album appendString:[NSString stringWithFormat:@" (%@)", [file objectForKey:@"date"]]];
            }
        }
        
        NSMutableString* title = [album mutableCopy];
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
                [self.sections addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:title, @"title", album, @"album", [[NSMutableArray alloc] init], @"files", nil]];
            }
        }
        
        [[[self.sections lastObject] objectForKey:@"files"] addObject:[NSNumber numberWithLong:i]];
    }
    
    [self.tableView reloadData];
    
    [self bufferMostNecessary];
    [self saveState];
}

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

- (void)bufferMostNecessary
{
    if (self.currentIndex != -1)
    {
        for (long i = self.currentIndex; i < [self.playlist count]; i++)
        {
            NSDictionary* item = [self.playlist objectAtIndex:i];
            MusicFileState state = [musicFileManager getState:item];
            if (state.state != MusicFileBuffered)
            {
                [musicFileManager buffer:item];
                return;
            }
        }
    }
    
    for (NSDictionary* item in self.playlist)
    {
        MusicFileState state = [musicFileManager getState:item];
        if (state.state != MusicFileBuffered)
        {
            [musicFileManager buffer:item];
            return;
        }
    }
    
    [musicFileManager stopBuffering];
}

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
                    [self setBufferingCell:cell backgroundViewForState:[musicFileManager getState:playlistItem]];
                }
            }
        }
    }
    
    [self tryToResumePlayingNowBufferingFile];
}

- (void)onMusicFileManagerBufferingCompleted
{
    [self bufferMostNecessary];
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
    
    MusicFileState state = [musicFileManager getState:[self.playlist objectAtIndex:self.currentIndex]];
    if (state.state == MusicFileBuffering)
    {
        [self playAtIndex:self.currentIndex atPosition:self.player.duration];
    }
}

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

- (void)scrobbleIfNecessary
{
    if (self.currentIndex == -1)
    {
        return;
    }
    
    if ([[NSDate date] timeIntervalSinceDate:self.playerStartedAt] >= MIN(self.player.duration / 2, 240))
    {
        [scrobbler scrobble:[self.playlist objectAtIndex:self.currentIndex] startedAt:self.playerStartedAt];
    }
}

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

- (void)updateCover
{
    if (self.currentIndex != -1 && self.nowPlayingInfo)
    {
        NSString* coverPath = [musicFileManager coverPath:[self.playlist objectAtIndex:self.currentIndex]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath])
        {
            MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc]
                                           initWithImage:[UIImage imageWithContentsOfFile:coverPath]];
            if (artwork)
            {
                [self.nowPlayingInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];
                [self updatedNowPlayingInfo];
            }
        }
    }
}

- (void)updatedNowPlayingInfo
{
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = self.nowPlayingInfo;
}

- (void)handleGoogleButtonTouchDown:(id)sender
{
    if (self.currentIndex != -1)
    {
        NSDictionary* item = [self.playlist objectAtIndex:self.currentIndex];
        NSString* query = [NSString stringWithFormat:@"%@ - %@ lyrics",
                           [item objectForKey:@"artist"], [item objectForKey:@"title"]];
        NSURL* url = [NSURL URLWithString:
                      [@"http://google.com/search?q=" stringByAppendingString:
                       [query stringByAddingPercentEncodingWithAllowedCharacters:
                        [NSCharacterSet URLHostAllowedCharacterSet]]]];
        [[UIApplication sharedApplication] openURL:url];
        [self closeToolbar];
    }
}

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
    self.playlistUndoHistory = [[NSMutableArray alloc] init];
}

- (IBAction)handleRotation:(UIRotationGestureRecognizer*)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateRecognized)
    {
        if (recognizer.rotation < -M_PI_4)
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
                [self _playlistChanged];
                
                [self.playlistUndoHistory removeLastObject];
                
                if (currentItemIsEqualToUndoItem)
                {
                    self.currentIndex = undoIndex;
                }
                else
                {
                    if (undoIndex != -1)
                    {
                        [self initAtIndex:undoIndex atPosition:undoPosition invalidatingPlaylistUndoHistory:NO];
                        if (undoWasPlaying)
                        {
                            [self.player play];
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
    }
}

- (void)showScrobblerEnabled
{
    if (scrobbler.enabled)
    {
        self.scrobblerButton.alpha = 1.0;
    }
    else
    {
        self.scrobblerButton.alpha = 0.2;
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

@end

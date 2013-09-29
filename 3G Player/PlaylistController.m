//
//  PlaylistController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "PlaylistController.h"

#import "Globals.h"

#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

@interface PlaylistController ()

@property (nonatomic, retain) NSMutableArray* playlist;
@property (nonatomic, retain) NSMutableArray* sections;

@property (nonatomic)         int currentIndex;
@property (nonatomic, retain) AVAudioPlayer* player;
@property (nonatomic, retain) NSDate* playerStartedAt;
@property (nonatomic)         BOOL playerInterruptedWhilePlaying;

@property (nonatomic)         enum { RepeatDisabled, RepeatPlaylist, RepeatTrack } repeat;

@property (nonatomic, retain) NSTimer* periodicTimer;

@property (nonatomic)         BOOL pausedByLowVolume;

@end

@implementation PlaylistController

@synthesize playlist;
@synthesize sections;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Playlist", NIL);
        
        self.playlist = [[NSMutableArray alloc] init];
        self.sections = [[NSMutableArray alloc] init];
        
        self.currentIndex = -1;
        self.player = nil;
        
        self.repeat = RepeatDisabled;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerStateChanged) name:@"stateChanged" object:musicFileManager];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerBufferingProgress:) name:@"bufferingProgress" object:musicFileManager];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerBufferingCompleted) name:@"bufferingCompleted" object:musicFileManager];
        
        self.pausedByLowVolume = FALSE;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    MPVolumeView* volumeView = [[MPVolumeView alloc] initWithFrame:self.volumeView.bounds];
    [self.volumeView addSubview:volumeView];
    [volumeView release];
    
    [self periodic];
    self.periodicTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(periodic) userInfo:nil repeats:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)addFiles:(NSArray*)files mode:(AddMode)addMode
{
    int index = [self.playlist count];
    if (addMode == AddAfterCurrentAlbum)
    {
        for (NSDictionary* section in self.sections)
        {
            BOOL isCurrentSection = NO;
            for (NSNumber* nsi in [section objectForKey:@"files"])
            {
                int i = [nsi intValue];
                
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
    
    for (NSDictionary* file in files)
    {
        [self.playlist insertObject:file atIndex:index];
        index++;
    }
    
    [self _playlistChanged];
}

- (void)clear
{    
    if (self.player)
    {
        if (self.player.playing)
        {
            [self scrobbleIfNecessary];
        }
        
        [self.player stop];
        self.player = nil;
    }
    
    [musicFileManager stopBuffering];
    
    [self.playlist removeAllObjects];
    [self _playlistChanged];
    
    self.currentIndex = -1;
    
    [self updateUI];
}

- (void)playAtIndex:(int)index
{
    [self playAtIndex:index atPosition:0];
}

- (void)playAtIndex:(int)index atPosition:(NSTimeInterval)position
{
    if (self.player)
    {
        if (self.player.playing)
        {
            [self scrobbleIfNecessary];
        }
        
        [self.player stop];
        self.player = nil;
    }
    
    self.currentIndex = index;
    NSDictionary* item = [self.playlist objectAtIndex:self.currentIndex];
    
    NSString* path = [musicFileManager getPath:item];
    if (path)
    {
        NSURL* url = [NSURL fileURLWithPath:path];
        self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
        self.player.delegate = self;
        if (position)
        {
            self.player.currentTime = position;
        }
        [self.player play];
        
        self.playerStartedAt = [NSDate date];
        [scrobbler sendNowPlaying:item];
    }
    
    [self.tableView reloadData];
    
    [self bufferMostNecessary];
}

- (void)periodic
{
    if (self.player)
    {
        Float32 volume;
        UInt32 dataSize = sizeof(Float32);
        AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareOutputVolume, &dataSize, &volume);
        
        if (self.player.playing)
        {
            if (volume < 0.25)
            {
                self.pausedByLowVolume = TRUE;
                [self.player pause];
            }
        }
        else
        {
            if (self.pausedByLowVolume && volume >= 0.25)
            {
                self.pausedByLowVolume = FALSE;
                [self.player play];
            }
        }
    }
    
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
            [self.player pause];
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

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer
{
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        int index = [self itemIndexForIndexPath:indexPath];
        if (index < self.currentIndex)
        {
            self.currentIndex--;
        }
        else if (index == self.currentIndex)
        {
            return;
        }
        [self.playlist removeObjectAtIndex:index];
        [self _playlistChanged];
    }
}

- (IBAction)handlePinch:(UIPinchGestureRecognizer*)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateEnded)
    {
        return;
    }
    
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
    [self playAtIndex:[self itemIndexForIndexPath:indexPath]];
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

#pragma mark - AVAudioPlayer delegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    MusicFileState state = [musicFileManager getState:[self.playlist objectAtIndex:self.currentIndex]];
    if (state.state == MusicFileBuffering)
    {
        [self tryToResumePlayingNowBufferingFile];
        return;
    }
    
    [self scrobbleIfNecessary];
    
    if (self.repeat != RepeatTrack)
    {
        self.currentIndex++;
        if (self.repeat == RepeatPlaylist)
        {
            self.currentIndex %= [self.playlist count];
        }
        
        if (!(self.currentIndex < [self.playlist count]))
        {
            self.currentIndex = -1;
            self.player = nil;
            
            [self.tableView reloadData];
        
            [self bufferMostNecessary];
        
            return;
        }
    }
    
    [self playAtIndex:self.currentIndex];
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
    self.playerInterruptedWhilePlaying = player.playing;
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player
{
    if (self.playerInterruptedWhilePlaying)
    {
        if (self.player)
        {
            [self.player play];
        }
        
        self.playerInterruptedWhilePlaying = NO;
    }
}

#pragma mark - Internals

- (void)_playlistChanged
{
    [self.sections removeAllObjects];

    for (int i = 0; i < [self.playlist count]; i++)
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
            ![title isEqualToString:[[self.sections lastObject] objectForKey:@"title"]]
        )
        {
            if ([self.sections count] > 0 && ![album isEqualToString:@""] && [album isEqualToString:[[self.sections lastObject] objectForKey:@"album"]])
            {
                [[self.sections lastObject] setObject:album forKey:@"title"];
            }
            else
            {
                [self.sections addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:title, @"title", album, @"album", [[NSMutableArray alloc] init], @"files", nil]];
            }
        }
        
        [[[self.sections lastObject] objectForKey:@"files"] addObject:[NSNumber numberWithInt:i]];
    }
    
    [self.tableView reloadData];
    
    [self bufferMostNecessary];
}

- (void)bufferMostNecessary
{
    if (self.currentIndex != -1)
    {
        for (int i = self.currentIndex; i < [self.playlist count]; i++)
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

- (int)itemIndexForIndexPath:(NSIndexPath*)indexPath
{
    return [[[[self.sections objectAtIndex:indexPath.section] objectForKey:@"files"] objectAtIndex:indexPath.row] integerValue];
}

- (NSDictionary*)itemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.playlist objectAtIndex:[self itemIndexForIndexPath:indexPath]];
}

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
    
    [self tryToResumePlayingNowBufferingFile];
}

- (void)onMusicFileManagerBufferingProgress:(NSNotification*)notification
{
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

- (void)scrobbleIfNecessary
{
    if ([[NSDate date] timeIntervalSinceDate:self.playerStartedAt] >= MIN(self.player.duration / 2, 240))
    {
        [scrobbler scrobble:[self.playlist objectAtIndex:self.currentIndex] startedAt:self.playerStartedAt];
    }
}

@end

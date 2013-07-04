//
//  PlaylistController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "PlaylistController.h"

#import "Globals.h"

#import <QuartzCore/QuartzCore.h>

@interface PlaylistController ()

@property (nonatomic, retain) NSMutableArray* playlist;
@property (nonatomic, retain) NSMutableArray* sections;

@property (nonatomic)         int currentIndex;
@property (nonatomic, retain) AVAudioPlayer* player;

@property (nonatomic)         enum { Disabled, Playlist, Track } repeat;

@property (nonatomic, retain) NSTimer* uiTimer;

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
        
        self.repeat = Disabled;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerStateChanged) name:@"stateChanged" object:musicFileManager];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerBufferingCompleted) name:@"bufferingCompleted" object:musicFileManager];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self updateUI];
    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateUI) userInfo:nil repeats:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)addFile:(NSDictionary*)file afterCurrent:(BOOL)afterCurrent
{
    [self _addFileToPlaylist:file];
    [self _playlistChanged];
}

- (void)addFiles:(NSArray*)files afterCurrent:(BOOL)afterCurrent
{
    for (NSDictionary* file in files)
    {
        [self _addFileToPlaylist:file];
    }
    
    [self _playlistChanged];
}

- (void)clear
{
    [self.playlist removeAllObjects];
    [self _playlistChanged];    
}

- (void)playAtIndex:(int)index
{
    [self playAtIndex:index atPosition:0];
}

- (void)playAtIndex:(int)index atPosition:(NSTimeInterval)position
{
    if (self.player)
    {
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
    }
    
    [self.tableView reloadData];
    
    [self bufferMostNecessary];
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
    }
    
    if (self.repeat == Disabled)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"repeat_disabled.png"] forState:UIControlStateNormal];
    }
    if (self.repeat == Playlist)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"repeat_playlist.png"] forState:UIControlStateNormal];
    }
    if (self.repeat == Track)
    {
        [self.repeatButton setImage:[UIImage imageNamed:@"repeat_track.png"] forState:UIControlStateNormal];
    }
}

- (IBAction)handlePositionSliderTouchUpInside:(id)sender
{
    self.player.currentTime = self.positionSlider.value;
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
    if (state.state == NotBuffered)
    {
        cell.textLabel.textColor = [UIColor grayColor];
    }
    if (state.state == Buffering)
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
    if (state.state == Buffered)
    {
    }
    
    if ([self itemIndexForIndexPath:indexPath] == self.currentIndex)
    {
        cell.textLabel.textColor = [UIColor orangeColor];
    }
}

#pragma mark - AVAudioPlayer delegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    MusicFileState state = [musicFileManager getState:[self.playlist objectAtIndex:self.currentIndex]];
    if (state.state == Buffering)
    {
        [self tryToResumePlayingNowBufferingFile];
        return;
    }
    
    self.currentIndex++;
    if (!(self.currentIndex < [self.playlist count]))
    {        
        [self.tableView reloadData];
        
        [self bufferMostNecessary];
        
        return;
    }
    
    [self playAtIndex:self.currentIndex];
}

#pragma mark - Internals

- (void)_addFileToPlaylist:(NSDictionary*)file
{
    [self.playlist addObject:file];
}

- (void)_playlistChanged
{
    [self.sections removeAllObjects];
        
    NSString* currentSection = @"<bad section>";
    for (int i = 0; i < [self.playlist count]; i++)
    {
        NSDictionary* file = [self.playlist objectAtIndex:i];
        
        NSArray* reversed = [[[[file objectForKey:@"path"] componentsSeparatedByString:@"/"] reverseObjectEnumerator] allObjects];
        NSString* sectionTitle = [[reversed subarrayWithRange:NSMakeRange(1, [reversed count] - 1)] componentsJoinedByString:@" < "];
        
        if (![sectionTitle isEqualToString:currentSection])
        {
            [self.sections addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:sectionTitle, @"title", [[NSMutableArray alloc] init], @"files", nil]];
            currentSection = sectionTitle;
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
            if (state.state != Buffered)
            {
                [musicFileManager buffer:item];
                return;
            }
        }
    }
    
    for (NSDictionary* item in self.playlist)
    {
        MusicFileState state = [musicFileManager getState:item];
        if (state.state != Buffered)
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
    if (state.state == Buffering)
    {
        [self playAtIndex:self.currentIndex atPosition:self.player.duration];
    }
}

@end

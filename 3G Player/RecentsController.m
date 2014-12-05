//
//  RecentsController.m
//  3G Player
//
//  Created by Admin on 12/4/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "RecentsController.h"

#import "Globals.h"

@interface RecentsController () <UIBarPositioningDelegate>

@property (nonatomic, retain) NSArray* recents;
@property (nonatomic, retain) IBOutlet UITableView *tableView;

@end

@implementation RecentsController

- (id)init
{
    self = [super init];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Recents", NIL);
        self.tabBarItem.image = [UIImage imageNamed:@"tabbar_recents.png"];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onMusicFileManagerStateChanged)
                                                     name:@"stateChanged"
                                                   object:musicFileManager];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateRecents)
                                                 name:@"recentsUpdated"
                                               object:musicTableService];
    [self updateRecents];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateRecents
{
    self.recents = [musicTableService readRecentsFile];
    [self.tableView reloadData];
}

#pragma mark — navbar positioning

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
    return UIBarPositionTopAttached;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.recents count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    return [musicTableService cellForMusicItem:item tableView:tableView];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //
}

#pragma mark - Gesture recognizer

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer
{
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        NSDictionary* item = [self getItemForIndexPath:indexPath];
        [musicTableService addItemToPlaylist:item mode:AddToTheEnd playAfter:NO];
    }
}

- (IBAction)handleLongPress:(UILongPressGestureRecognizer*)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateBegan)
    {
        return;
    }
    
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        NSDictionary* item = [self getItemForIndexPath:indexPath];        
        [musicTableService showActionSheetForItem:item inView:self.view];
    }
}

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.recents objectAtIndex:indexPath.row];
}

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
}

@end

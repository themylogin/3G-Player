//
//  RecentsController.m
//  3G Player
//
//  Created by Admin on 12/4/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "SearchController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"

@interface SearchController () <UIBarPositioningDelegate>

@property (nonatomic, retain) NSArray* results;
@property (nonatomic, retain) IBOutlet UITableView *tableView;

@end

@implementation SearchController

- (id)init
{
    self = [super init];
    if (self)
    {
        self.results = [NSArray array];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = libraryRightBarButtonItem;
    self.toolbarItems = [NSArray arrayWithObject:libraryToolbarButtonItem];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    controllers.library.librarySearchBar.text = self.title;
    [controllers.library.librarySearchBar becomeFirstResponder];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setSearchQuery:(NSString*)query results:(NSArray*)results;
{
    self.title = query;
    self.results = results;
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
    return [self.results count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    return [musicTableService cellForMusicItem:item tableView:tableView];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    
    LibraryPageController* controller = [[LibraryPageController alloc]
                                         initWithDirectory:[item objectForKey:@"path"]
                                         title:[item objectForKey:@"name"]];
    [controllers.library pushViewController:controller animated:YES];
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
        [musicTableService showActionSheetForItem:item
                                           inView:self.view
                                 withExtraButtons:BlacklistExtraButton];
    }
}

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.results objectAtIndex:indexPath.row];
}

@end

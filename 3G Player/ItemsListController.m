//
//  ItemsListController.m
//  3G Player
//
//  Created by Admin on 3/30/16.
//  Copyright (c) 2016 themylogin. All rights reserved.
//

#import "ItemsListController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"

@interface ItemsListController ()

@end

@implementation ItemsListController

@synthesize items = _items;

- (id)init
{
    self = [super init];
    if (self)
    {
        self.items = [NSArray array];
    }
    return self;
}

- (NSArray*)items
{
    return _items;
}

- (void)setItems:(NSArray *)items
{
    if (items != _items)
    {
        [items retain];
        [_items release];
        
        _items = items;
        [self.tableView reloadData];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.items count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    return [musicTableService cellForMusicItem:item tableView:tableView showFullPath:true];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    [controllers.library navigateToItem:item enter:YES];
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

#pragma mark - Internals

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.items objectAtIndex:indexPath.row];
}

@end

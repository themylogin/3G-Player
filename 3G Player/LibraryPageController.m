//
//  LibraryPageController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "LibraryPageController.h"

#import "Globals.h"

@interface LibraryPageController ()

@property (nonatomic, retain) NSString* directory;

@property (nonatomic, retain) NSArray* index;
@property (nonatomic, retain) NSMutableArray* indexLetters;
@property (nonatomic, retain) NSMutableDictionary* indexRowsForLetters;

@end

@implementation LibraryPageController

- (id)initWithDirectory:(NSString*)directory title:(NSString*)title
{
    self = [super initWithNibName:@"LibraryPageController" bundle:nil];
    if (self)
    {
        self.directory = directory;
        self.title = title;
        
        self.index = [musicTableService loadIndexFor:self.directory];
        
        self.indexLetters = [NSMutableArray array];
        self.indexRowsForLetters = [NSMutableDictionary dictionary];
        for (int i = 0; i < [self.index count]; i++)
        {
            NSDictionary* item = [self.index objectAtIndex:i];
            if ([musicTableService isDirectory:item])
            {
                NSString* letter = [[[item objectForKey:@"name"] substringToIndex:1] uppercaseString];
                if (![self.indexRowsForLetters objectForKey:letter])
                {
                    [self.indexLetters addObject:letter];
                    [self.indexRowsForLetters setObject:[NSNumber numberWithInt:i] forKey:letter];
                }
            }
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMusicFileManagerStateChanged) name:@"stateChanged" object:musicFileManager];
    }
    return self;
}

- (void)dealloc
{
    self.directory = nil;
    self.index = nil;
    
    [super dealloc];
}

- (BOOL)update
{
    self.index = [musicTableService loadIndexFor:self.directory];
    if ([self.index count] > 0)
    {
        [self.tableView reloadData];
        return TRUE;
    }
    else
    {
        return FALSE;
    }
}

- (void)scrollToItem:(NSDictionary*)item
{
    for (int i = 0; i < [self.index count]; i++)
    {
        if ([[[self.index objectAtIndex:i] objectForKey:@"path"] isEqualToString:[item objectForKey:@"path"]])
        {
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]
                                  atScrollPosition:UITableViewScrollPositionTop
                                          animated:NO];
            break;
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
 
    self.navigationItem.rightBarButtonItem = updateLibraryButton;
    self.toolbarItems = [NSArray arrayWithObject:updateLibraryProgress];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSArray*)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    return self.indexLetters;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.index count];
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    [tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[[self.indexRowsForLetters objectForKey:title] integerValue] inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
    return index;
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
    if ([musicTableService isDirectory:item])
    {
        if ([musicTableService isBlacklisted:item])
        {
            return;
        }
        
        LibraryPageController* libraryPageController = [[LibraryPageController alloc] initWithDirectory:[item objectForKey:@"path"] title:[item objectForKey:@"name"]];
        [self.navigationController pushViewController:libraryPageController animated:YES];
        [libraryPageController release];
    }
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

- (IBAction)handleRotation:(UIRotationGestureRecognizer*)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateRecognized && recognizer.rotation > M_PI_2)
    {
        bool everythingIsBlacklisted = YES;
        for (NSDictionary* item in self.index)
        {
            if (![musicTableService isBlacklisted:item])
            {
                everythingIsBlacklisted = NO;
                break;
            }
        }
        
        if (everythingIsBlacklisted)
        {
            for (NSDictionary* item in self.index)
            {
                [musicTableService unblacklistItem:item];
            }
        }
        else
        {
            for (NSDictionary* item in self.index)
            {
                [musicTableService blacklistItem:item];
            }
        }
    }
}

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.index objectAtIndex:indexPath.row];
}

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
}

@end

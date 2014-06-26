//
//  LibraryPageController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "LibraryPageController.h"

#import "Globals.h"

#import "JSONKit.h"

#import <objc/runtime.h>

@interface LibraryPageController ()


@property (nonatomic, retain) NSString* directory;

@property (nonatomic, retain) NSFileManager* fileManager;

@property (nonatomic, retain) NSArray* index;
@property (nonatomic, retain) NSMutableArray* indexLetters;
@property (nonatomic, retain) NSMutableDictionary* indexRowsForLetters;

@end

static char const* const ALERTVIEW = "ALERTVIEW";
static char const* const ADD_MODE = "ADD_MODE";
static char const* const DIRECTORY = "DIRECTORY";
static char const* const ITEM = "ITEM";
static char const* const PLAY_AFTER = "PLAY_AFTER";

@implementation LibraryPageController

- (id)initWithDirectory:(NSString*)directory title:(NSString*)title
{
    self = [super initWithNibName:@"LibraryPageController" bundle:nil];
    if (self)
    {
        self.directory = directory;
        self.title = title;
        
        self.fileManager = [NSFileManager defaultManager];
        
        self.index = [self loadIndexFor:self.directory];
        
        self.indexLetters = [NSMutableArray array];
        self.indexRowsForLetters = [NSMutableDictionary dictionary];
        for (int i = 0; i < [self.index count]; i++)
        {
            NSDictionary* item = [self.index objectAtIndex:i];
            if ([self isDirectory:item])
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
    self.index = [self loadIndexFor:self.directory];
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
    static NSString* cellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil)
    {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
    }
        
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    if ([self isDirectory:item])
    {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if ([self isBlacklisted:item])
        {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        else
        {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    }
    else
    {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    if ([self isBuffered:item])
    {        
        cell.textLabel.textColor = [UIColor blackColor];
    }
    else if ([self isBlacklisted:item])
    {
        cell.textLabel.textColor = [UIColor colorWithRed:0.85 green:0.85 blue:0.85 alpha:1.0];
    }
    else
    {        
        cell.textLabel.textColor = [UIColor grayColor];
    }
    cell.textLabel.text = [item objectForKey:@"name"];
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    if ([self isDirectory:item])
    {
        if ([self isBlacklisted:item])
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
        if ([self isDirectory:item])
        {
            [self addDirectoryToPlaylist:[item objectForKey:@"path"] mode:AddToTheEnd askConfirmation:YES playAfter:FALSE];
        }
        else
        {
            [controllers.current addFiles:[NSArray arrayWithObject:item] mode:AddToTheEnd];
        }
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
        
        if ([self isBlacklisted:item])
        {
            UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Question", nil)
                                                            message:[NSString stringWithFormat:NSLocalizedString(@"Remove «%@» from blacklist?", nil), [item objectForKey:@"name"]]
                                                           delegate:self
                                                  cancelButtonTitle:NSLocalizedString(@"No", nil)
                                                  otherButtonTitles:NSLocalizedString(@"Yes", nil), nil];
            objc_setAssociatedObject(alert, ALERTVIEW, @"REMOVE_FROM_BLACKLIST", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(alert, ITEM, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [alert show];
            [alert release];
            return;
        }
        
        UIActionSheet* actionSheet = [[UIActionSheet alloc] initWithTitle:[item objectForKey:@"name"]
                                                                 delegate:self
                                                        cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                                   destructiveButtonTitle:nil
                                                        otherButtonTitles:NSLocalizedString(@"Replace", nil),
                                                                          NSLocalizedString(@"Replace and play", nil),
                                                                          NSLocalizedString(@"Add", nil),
                                                                          NSLocalizedString(@"Add after current album", nil),
                                                                          NSLocalizedString(@"Add after current track", nil),
                                                                          NSLocalizedString(@"Blacklist", nil),
                                                                          NSLocalizedString(@"Delete", nil),
                                                                          nil];
        actionSheet.destructiveButtonIndex = 6;
        objc_setAssociatedObject(actionSheet, ITEM, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [actionSheet showInView:[self.view window]];
        [actionSheet release];        
    }
}

- (IBAction)handleRotation:(UIRotationGestureRecognizer*)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateRecognized && recognizer.rotation > M_PI_2)
    {
        bool everythingIsBlacklisted = YES;
        for (NSDictionary* item in self.index)
        {
            if (![self isBlacklisted:item])
            {
                everythingIsBlacklisted = NO;
                break;
            }
        }
        
        if (everythingIsBlacklisted)
        {
            for (NSDictionary* item in self.index)
            {
                [self unblacklistItem:item];
            }
        }
        else
        {
            for (NSDictionary* item in self.index)
            {
                [self blacklistItem:item];
            }
        }
    }
}

#pragma mark - Action sheet delegate

- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    const int REPLACE           = 0;
    const int REPLACE_AND_PLAY  = 1;
    const int ADD __unused      = 2;
    const int ADD_AFTER_ALBUM   = 3;
    const int ADD_AFTER_TRACK   = 4;
    const int BLACKLIST         = 5;
    const int DELETE            = 6;
    const int CANCEL            = 7;
    
    if (buttonIndex == CANCEL)
    {
        return;
    }
    
    NSDictionary* item = objc_getAssociatedObject(actionSheet, ITEM);
    
    if (buttonIndex == DELETE)
    {
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Question", nil)
                                                        message:[NSString stringWithFormat:NSLocalizedString(@"Delete «%@»?", nil), [item objectForKey:@"name"]]
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"No", nil)
                                              otherButtonTitles:NSLocalizedString(@"Yes", nil), nil];
        objc_setAssociatedObject(alert, ALERTVIEW, @"DELETE", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(alert, ITEM, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [alert show];
        [alert release];
        return;
    }
    
    if (buttonIndex == BLACKLIST)
    {
        [self blacklistItem:item];
        return;
    }
    
    if (buttonIndex == REPLACE || buttonIndex == REPLACE_AND_PLAY)
    {
        [controllers.current clear];
    }
    
    AddMode addMode = AddToTheEnd;
    if (buttonIndex == ADD_AFTER_ALBUM)
    {
        addMode = AddAfterCurrentAlbum;
    }
    if (buttonIndex == ADD_AFTER_TRACK)
    {
        addMode = AddAfterCurrentTrack;
    }
    
    if ([self isDirectory:item])
    {
        [self addDirectoryToPlaylist:[item objectForKey:@"path"] mode:addMode askConfirmation:YES playAfter:buttonIndex == REPLACE_AND_PLAY];
    }
    else
    {
        [controllers.current addFiles:[NSArray arrayWithObject:item] mode:addMode];
        if (buttonIndex == REPLACE_AND_PLAY)
        {
            [controllers.current playAtIndex:0];
        }
    }
}

#pragma mark - Alert view delegage

- (void)alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    NSString* view = objc_getAssociatedObject(alertView, ALERTVIEW);
    
    if ([view isEqualToString:@"ADD"])
    {
        if (buttonIndex == 1)
        {
            [self addDirectoryToPlaylist:objc_getAssociatedObject(alertView, DIRECTORY) mode:[objc_getAssociatedObject(alertView, ADD_MODE) intValue] askConfirmation:NO playAfter:[objc_getAssociatedObject(alertView, PLAY_AFTER) boolValue]];
        }
    }
    
    if ([view isEqualToString:@"DELETE"])
    {
        if (buttonIndex == 1)
        {
            [musicFileManager deleteFileOrdirectory:objc_getAssociatedObject(alertView, ITEM)];
        }
    }
    
    if ([view isEqualToString:@"REMOVE_FROM_BLACKLIST"])
    {
        if (buttonIndex == 1)
        {
            [self unblacklistItem:objc_getAssociatedObject(alertView, ITEM)];
        }
    }
}

#pragma mark - Internals

- (NSArray*)loadIndexFor:(NSString*)path
{
    NSString* indexJsonPath = [[[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:path] stringByAppendingString:@"/index.json"];
    if ([self.fileManager fileExistsAtPath:indexJsonPath])
    {
        NSDictionary* index = [[JSONDecoder decoder] objectWithData:[NSData dataWithContentsOfFile:indexJsonPath]];
        return [[index allValues] sortedArrayUsingComparator: ^(id _a, id _b)
                {
                    NSDictionary* a = (NSDictionary*) _a;
                    NSDictionary* b = (NSDictionary*) _b;
                         
                    if ([[a objectForKey:@"type"] isEqualToString:@"directory"] && [[b objectForKey:@"type"] isEqualToString:@"file"])
                    {
                        return (NSComparisonResult)NSOrderedAscending;
                    }
                    if ([[a objectForKey:@"type"] isEqualToString:@"file"] && [[b objectForKey:@"type"] isEqualToString:@"directory"])
                    {
                        return (NSComparisonResult)NSOrderedDescending;
                    }
                    return [[a objectForKey:@"name"] compare:[b objectForKey:@"name"] options:NSCaseInsensitiveSearch];
                }];
    }
    else
    {
        return [[[NSArray alloc] init] autorelease];
    }
}

- (void)addDirectoryToPlaylist:(NSString*)directory mode:(AddMode)addMode askConfirmation:(BOOL)ask playAfter:(BOOL)play
{
    NSMutableArray* filesToAdd = [[NSMutableArray alloc] init];
    
    if ([self addDirectory:directory to:filesToAdd askConfirmation:ask])
    {
        [controllers.current addFiles:filesToAdd mode:addMode];
        
        if (play)
        {
            [controllers.current playAtIndex:0];
        }
    }
    else
    {        
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Question", nil)
                                                        message:[NSString stringWithFormat:NSLocalizedString(@"Directory «%@» contains lots of music. Add it anyway?", nil), directory]
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"No", nil)
                                              otherButtonTitles:NSLocalizedString(@"Yes", nil), nil];
        objc_setAssociatedObject(alert, ALERTVIEW, @"ADD", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(alert, DIRECTORY, directory, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(alert, ADD_MODE, [NSNumber numberWithInt:addMode], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(alert, PLAY_AFTER, [NSNumber numberWithBool:play], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [alert show];
        [alert release];
    }
    
    [filesToAdd release];
}

- (BOOL)addDirectory:(NSString*)directory to:(NSMutableArray*)playlist askConfirmation:(BOOL)ask
{
    @autoreleasepool
    {
        for (NSDictionary* item in [self loadIndexFor:directory])
        {
            if ([self isBlacklisted:item])
            {
                continue;
            }
            
            if ([self isDirectory:item])
            {
                if (![self addDirectory:[item objectForKey:@"path"] to:playlist askConfirmation:ask])
                {
                    return FALSE;
                }
            }
            else
            {
                [playlist addObject:item];
                if (ask && playlist.count > 128)
                {
                    [playlist removeAllObjects];
                    return FALSE;
                }
            }
        }
        
        return TRUE;
    }
}

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.index objectAtIndex:indexPath.row];
}

- (BOOL)isDirectory:(NSDictionary*)item
{
    return [[item objectForKey:@"type"] isEqualToString:@"directory"];
}

- (NSString*)blacklistFilePath:(NSDictionary*)item
{
    if ([self isDirectory:item])
    {
        return [[[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[item objectForKey:@"path"]] stringByAppendingString:@"/blacklisted"];
    }
    else
    {
        return [[[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[item objectForKey:@"path"]] stringByAppendingString:@".blacklisted"];
    }
}

- (BOOL)isBlacklisted:(NSDictionary*)item
{
    return [self.fileManager fileExistsAtPath:[self blacklistFilePath:item] isDirectory:nil];
}

- (void)blacklistItem:(NSDictionary*)item
{
    [self.fileManager createFileAtPath:[self blacklistFilePath:item] contents:nil attributes:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"stateChanged" object:musicFileManager];
}

- (void)unblacklistItem:(NSDictionary*)item
{
    [self.fileManager removeItemAtPath:[self blacklistFilePath:item] error:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"stateChanged" object:musicFileManager];
}

- (BOOL)isBuffered:(NSDictionary*)item
{
    if ([self isDirectory:item])
    {
        return [self directoryIsBuffered:item];
    }
    else
    {
        return [self fileIsBuffered:item];
    }
}

- (BOOL)directoryIsBuffered:(NSDictionary*)item
{
    @autoreleasepool
    {
        for (NSDictionary* childItem in [self loadIndexFor:[item objectForKey:@"path"]])
        {
            if ([self isBlacklisted:childItem])
            {
                continue;
            }
            
            if ([self isDirectory:childItem])
            {                
                if (![self directoryIsBuffered:childItem])
                {
                    return NO;
                }
            }
            else
            {
                if (![self fileIsBuffered:childItem])
                {
                    return NO;
                }
            }
        }
        
        return YES;
    }
}

- (BOOL)fileIsBuffered:(NSDictionary*)item
{
    return [musicFileManager getState:item].state == MusicFileBuffered;
}

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
}

@end

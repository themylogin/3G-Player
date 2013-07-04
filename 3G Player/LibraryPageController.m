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

@end

static char const* const AFTER_CURRENT = "AFTER_CURRENT";
static char const* const DIRECTORY = "DIRECTORY";
static char const* const ITEM = "ITEM";

@implementation LibraryPageController

- (id)initWithDirectory:(NSString*)directory title:(NSString*)title
{
    self = [super init];
    if (self)
    {
        self.directory = directory;
        self.title = title;
        
        self.fileManager = [NSFileManager defaultManager];
        
        self.index = [self loadIndexFor:self.directory];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.index count];
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
    }
    else
    {
        cell.accessoryType = UITableViewCellAccessoryNone;
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
        LibraryPageController* libraryPageController = [[LibraryPageController alloc] initWithDirectory:[item objectForKey:@"path"] title:[item objectForKey:@"name"]];
        [self.navigationController pushViewController:libraryPageController animated:YES];
        [libraryPageController release];
    }
    // else
    // {
    //     [controllers.playlist addFile:item afterCurrent:NO];
    // }
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
            [self addDirectoryToPlaylist:[item objectForKey:@"path"] afterCurrent:NO askConfirmation:YES];
        }
        else
        {
            [controllers.playlist addFile:item afterCurrent:NO];
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
        
        UIActionSheet* actionSheet = [[UIActionSheet alloc] initWithTitle:[item objectForKey:@"name"]
                                                                 delegate:self
                                                        cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                                   destructiveButtonTitle:NSLocalizedString(@"Delete", nil)
                                                        otherButtonTitles:NSLocalizedString(@"Add", nil),
                                                                          NSLocalizedString(@"Add after current", nil),
                                                                          NSLocalizedString(@"Replace", nil),
                                                                          NSLocalizedString(@"Replace and play", nil),
                                                                          nil];
        objc_setAssociatedObject(actionSheet, ITEM, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [actionSheet showInView:[self.view window]];
        [actionSheet release];        
    }
}

#pragma mark - Action sheet delegate

- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    const int DELETE            = 0;
    const int ADD               = 1;
    const int ADD_AFTER_CURRENT = 2;
    const int REPLACE           = 3;
    const int REPLACE_AND_PLAY  = 4;
    const int CANCEL            = 5;
    
    if (buttonIndex == CANCEL)
    {
        return;
    }
    
    NSDictionary* item = objc_getAssociatedObject(actionSheet, ITEM);
    
    if (buttonIndex == DELETE)
    {
        NSString* path = [[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[item objectForKey:@"path"]];
        if ([self isDirectory:item])
        {        
            NSDirectoryEnumerator* de = [[NSFileManager defaultManager] enumeratorAtPath:path];
            while (true)
            {
                NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            
                NSString* file = [de nextObject];
                if (!file)
                {
                    break;
                }
                
                NSString* filePath = [[path stringByAppendingString:@"/"] stringByAppendingString:file];
            
                BOOL isDirectory;
                if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory] && !isDirectory)
                {
                    NSString* fileName = [[file pathComponents] lastObject];
                    if (!([fileName isEqualToString:@"index.json"] || [fileName isEqualToString:@"index.json.checksum"]))
                    {
                        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                    }
                }
            
                [pool drain];
            }
        }
        else
        {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@".incomplete"] error:nil];
        }
        
        return;
    }
    
    if (buttonIndex == REPLACE || buttonIndex == REPLACE_AND_PLAY)
    {
        [controllers.playlist clear];
    }
    
    BOOL afterCurrent = (buttonIndex == ADD_AFTER_CURRENT);
    if ([self isDirectory:item])
    {
        [self addDirectoryToPlaylist:[item objectForKey:@"path"] afterCurrent:afterCurrent askConfirmation:YES];
    }
    else
    {
        [controllers.playlist addFile:item afterCurrent:afterCurrent];
    }
        
    if (buttonIndex == REPLACE_AND_PLAY)
    {
        
    }
}

#pragma mark - Alert view delegage

- (void)alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1)
    {
        [self addDirectoryToPlaylist:objc_getAssociatedObject(alertView, DIRECTORY) afterCurrent:[objc_getAssociatedObject(alertView, AFTER_CURRENT) boolValue] askConfirmation:NO];
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

- (void) addDirectoryToPlaylist:(NSString*)directory afterCurrent:(BOOL)afterCurrent askConfirmation:(BOOL)ask
{
    NSMutableArray* filesToAdd = [[NSMutableArray alloc] init];
    
    if ([self addDirectory:directory to:filesToAdd askConfirmation:ask])
    {
        [controllers.playlist addFiles:filesToAdd afterCurrent:afterCurrent];
    }
    else
    {        
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Question", nil)
                                                        message:[NSString stringWithFormat:NSLocalizedString(@"Directory «%@» contains lots of music. Add it anyway?", nil), directory]
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"No", nil)
                                              otherButtonTitles:NSLocalizedString(@"Yes", nil), nil];
        objc_setAssociatedObject(alert, DIRECTORY, directory, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(alert, AFTER_CURRENT, [NSNumber numberWithBool:afterCurrent], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [alert show];
        [alert release];
    }
    
    [filesToAdd release];
}

- (BOOL) addDirectory:(NSString*)directory to:(NSMutableArray*)playlist askConfirmation:(BOOL)ask
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    for (NSDictionary* item in [self loadIndexFor:directory])
    {
        if ([self isDirectory:item])
        {
            if (![self addDirectory:[item objectForKey:@"path"] to:playlist askConfirmation:ask])
            {
                [pool drain];
                return FALSE;
            }
        }
        else
        {
            [playlist addObject:item];
            if (ask && playlist.count > 128)
            {
                [playlist removeAllObjects];
                [pool drain];
                return FALSE;
            }
        }
    }
    
    [pool drain];
    return TRUE;
}

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.index objectAtIndex:indexPath.row];
}

- (BOOL)isDirectory:(NSDictionary*)item
{
    return [[item objectForKey:@"type"] isEqualToString:@"directory"];
}

@end

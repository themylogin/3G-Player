//
//  MusicTableService.m
//  3G Player
//
//  Created by Admin on 12/4/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "MusicTableService.h"

#import "Globals.h"
#import "LibraryPageController.h"

#import <objc/runtime.h>

static char const* const ALERTVIEW = "ALERTVIEW";
static char const* const ADD_MODE = "ADD_MODE";
static char const* const BUTTONS = "BUTTONS";
static char const* const DIRECTORY = "DIRECTORY";
static char const* const ITEM = "ITEM";
static char const* const PLAY_AFTER = "PLAY_AFTER";

@interface MusicTableService ()

@property (nonatomic, retain) NSFileManager* fileManager;

@end

@implementation MusicTableService

- (id)init
{
    self.fileManager = [NSFileManager defaultManager];
    
    return self;
}

#pragma mark - Index

- (NSDictionary*)loadRawIndexForPlayer:(NSDictionary*)player directory:(NSString*)directory
{
    NSString* indexJsonPath = [librariesPath stringByAppendingString:
                               [[player objectForKey:@"libraryPath"] stringByAppendingString:
                                [NSString stringWithFormat:@"/%@/index.json", directory]]];
    if ([self.fileManager fileExistsAtPath:indexJsonPath])
    {
        return [NSJSONSerialization
                JSONObjectWithData:[NSData dataWithContentsOfFile:indexJsonPath]
                options:0
                error:nil];
    }
    else
    {
        return [NSDictionary dictionary];
    }
}

- (NSArray*)loadIndexForPlayer:(NSDictionary*)player directory:(NSString*)directory
{
    NSDictionary* index = [self loadRawIndexForPlayer:player directory:directory];
    
    NSArray* values = [index allValues];
    NSMutableArray* valuesWithPlayer = [[[NSMutableArray alloc] initWithCapacity:values.count] autorelease];
    for (int i = 0; i < values.count; i++)
    {
        [valuesWithPlayer addObject:[self annotateItem:[values objectAtIndex:i] withPlayer:player]];
    }
    
    return [valuesWithPlayer sortedArrayUsingComparator: ^(id _a, id _b)
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
                if ([[a objectForKey:@"type"] isEqualToString:@"file"] && [[b objectForKey:@"type"] isEqualToString:@"file"] &&
                    ![[a objectForKey:@"disc"] isEqual:[b objectForKey:@"disc"]])
                {
                    return [[a objectForKey:@"disc"] compare:[b objectForKey:@"disc"]];
                }
                return [[a objectForKey:@"name"] compare:[b objectForKey:@"name"] options:NSCaseInsensitiveSearch];
            }];
}

- (NSArray*)loadIndexForItem:(NSDictionary*)item
{
    return [self loadIndexForPlayer:[item objectForKey:@"player"] directory:[item objectForKey:@"path"]];
}

- (NSDictionary*)annotateItem:(NSDictionary*)item withPlayer:(NSDictionary*)player
{
    NSMutableDictionary* value = [[item mutableCopy] autorelease];
    [value setObject:player forKey:@"player"];
    return value;
}

#pragma mark - Any music controller

- (UITableViewCell*)cellForMusicItem:(NSDictionary*)item tableView:(UITableView *)tableView
{
    return [self cellForMusicItem:item tableView:tableView showFullPath:false];
}

- (UITableViewCell*)cellForMusicItem:(NSDictionary*)item tableView:(UITableView *)tableView showFullPath:(bool)showFullPath
{
    static NSString* cellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil)
    {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
    }
    
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
    if (showFullPath)
    {
        cell.textLabel.text = [musicFileManager navigationPathForItem:item];
    }
    else
    {
        cell.textLabel.text = [item objectForKey:@"name"];
    }
    
    return cell;
}

- (void)showActionSheetForItem:(NSDictionary*)item inView:(UIView*)view withExtraButtons:(int)extraButtons;
{
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
                                                    cancelButtonTitle:nil
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:nil];
    NSMutableArray* buttons = [NSMutableArray array];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Replace", nil)];
    [buttons addObject:@"REPLACE"];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Replace and play", nil)];
    [buttons addObject:@"REPLACE_AND_PLAY"];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Add", nil)];
    [buttons addObject:@"ADD"];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Add after current album", nil)];
    [buttons addObject:@"ADD_AFTER_ALBUM"];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Add after current track", nil)];
    [buttons addObject:@"ADD_AFTER_TRACK"];
    
    if ([controllers.current canAddAfterAdded])
    {
        [actionSheet addButtonWithTitle:NSLocalizedString(@"Add after just added", nil)];
        [buttons addObject:@"ADD_AFTER_ADDED"];
    }
    
    if (!([UIScreen mainScreen].bounds.size.height == 480 && [buttons count] >= 6))
    {
        if (extraButtons & BlacklistExtraButton)
        {
            [actionSheet addButtonWithTitle:NSLocalizedString(@"Blacklist", nil)];
            [buttons addObject:@"BLACKLIST"];
        }
    }
    
    [buttons addObject:@"DELETE"];
    actionSheet.destructiveButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Delete", nil)];
    
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    
    objc_setAssociatedObject(actionSheet, BUTTONS, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(actionSheet, ITEM, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [actionSheet showInView:[view window]];
    [actionSheet release];
}

- (void)alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    NSString* view = objc_getAssociatedObject(alertView, ALERTVIEW);
    
    if ([view isEqualToString:@"ADD"])
    {
        if (buttonIndex == 1)
        {
            [self addDirectoryToPlaylist:objc_getAssociatedObject(alertView, DIRECTORY)
                                    mode:[objc_getAssociatedObject(alertView, ADD_MODE) intValue]
                         askConfirmation:NO
                               playAfter:[objc_getAssociatedObject(alertView, PLAY_AFTER) boolValue]];
        }
    }
    
    if ([view isEqualToString:@"DELETE"])
    {
        if (buttonIndex == 1)
        {
            [musicFileManager remove:objc_getAssociatedObject(alertView, ITEM)];
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

- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSArray* buttons = objc_getAssociatedObject(actionSheet, BUTTONS);
    if (buttonIndex >= [buttons count])
    {
        return;
    }
    
    NSString* button = [buttons objectAtIndex:buttonIndex];    
    
    NSDictionary* item = objc_getAssociatedObject(actionSheet, ITEM);
    
    if ([button isEqualToString:@"DELETE"])
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
    
    if ([button isEqualToString:@"BLACKLIST"])
    {
        [self blacklistItem:item];
        return;
    }
    
    if ([button isEqualToString:@"REPLACE"] || [button isEqualToString:@"REPLACE_AND_PLAY"])
    {
        [controllers.current clear];
    }
    
    AddMode addMode = AddToTheEnd;
    if ([button isEqualToString:@"ADD_AFTER_ALBUM"])
    {
        addMode = AddAfterCurrentAlbum;
    }
    if ([button isEqualToString:@"ADD_AFTER_TRACK"])
    {
        addMode = AddAfterCurrentTrack;
    }
    if ([button isEqualToString:@"ADD_AFTER_ADDED"])
    {
        addMode = AddAfterJustAdded;
    }
    
    [self addItemToPlaylist:item mode:addMode playAfter:[button isEqualToString:@"REPLACE_AND_PLAY"]];
}

#pragma mark - Add to playlist

- (void)addItemToPlaylist:(NSDictionary*)item mode:(AddMode)addMode playAfter:(BOOL)playAfter
{
    if ([self isDirectory:item])
    {
        [self addDirectoryToPlaylist:item mode:addMode askConfirmation:YES playAfter:playAfter];
    }
    else
    {
        [controllers.current addFiles:[NSArray arrayWithObject:item] mode:addMode];
        if (playAfter)
        {
            [controllers.current playAtIndex:0];
        }
    }
    
    [musicFileManager notifyItemAdd:item];
}

- (void)addDirectoryToPlaylist:(NSDictionary*)directory mode:(AddMode)addMode askConfirmation:(BOOL)ask playAfter:(BOOL)play
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
                                                        message:[NSString stringWithFormat:NSLocalizedString(@"Directory «%@» contains lots of music. Add it anyway?", nil), [directory objectForKey:@"name"]]
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

- (BOOL)addDirectory:(NSDictionary*)directory to:(NSMutableArray*)playlist askConfirmation:(BOOL)ask
{
    @autoreleasepool
    {
        for (NSDictionary* item in [self loadIndexForItem:directory])
        {
            if ([self isBlacklisted:item])
            {
                continue;
            }
            
            if ([self isDirectory:item])
            {
                if (![self addDirectory:item to:playlist askConfirmation:ask])
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

#pragma mark - Helpers

- (BOOL)isDirectory:(NSDictionary*)item
{
    return [[item objectForKey:@"type"] isEqualToString:@"directory"];
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

- (NSString*)blacklistFilePath:(NSDictionary*)item
{
    if ([self isDirectory:item])
    {
        return [[musicFileManager absolutePath:item] stringByAppendingString:@"/blacklisted"];
    }
    else
    {
        return [[musicFileManager absolutePath:item] stringByAppendingString:@".blacklisted"];
    }
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
        for (NSDictionary* childItem in [self loadIndexForItem:item])
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
    return [musicFileManager state:item].state == MusicFileBuffered;
}

@end

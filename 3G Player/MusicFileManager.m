//
//  MusicFileManager.m
//  3G Player
//
//  Created by Admin on 7/4/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "MusicFileManager.h"

#import <MediaPlayer/MediaPlayer.h>

#import "Globals.h"
#import "KeepAliver.h"

#import "ASIHTTPRequest.h"

@interface MusicFileManager ()

@property (nonatomic, retain) NSFileManager*        fileManager;
@property (nonatomic, retain) NSNotificationCenter* notificationCenter;

@property (nonatomic, retain) NSDictionary*     bufferingFile;
@property (nonatomic)         bool              bufferingIsError;
@property (nonatomic)         uint              bufferingExpectedLength;

@property (nonatomic, retain) ASIHTTPRequest*   bufferingRequest;
@property (nonatomic, retain) NSFileHandle*     bufferingFileHandle;
@property (nonatomic, retain) KeepAliver*       bufferingKeepAliver;

@property (nonatomic, retain) NSString*         addHistoryFile;
@property (nonatomic, retain) NSString*         playHistoryFile;

@end

@implementation MusicFileManager

- (id)init
{
    self.fileManager = [NSFileManager defaultManager];
    self.notificationCenter = [NSNotificationCenter defaultCenter];
    
    self.bufferingFile = nil;
    self.bufferingIsError = false;
    self.bufferingExpectedLength = 0;
    
    self.bufferingRequest = nil;
    self.bufferingFileHandle = nil;
    
    self.bufferingKeepAliver = [[KeepAliver alloc] init];
    
    self.addHistoryFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]
                           stringByAppendingString:@"/add_history.json"];
    self.playHistoryFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]
                            stringByAppendingString:@"/play_history.json"];
    if (![self.fileManager fileExistsAtPath:self.addHistoryFile])
    {
        [self writeHistoryFile:self.addHistoryFile history:[NSArray array]];
    }
    
    if (![self.fileManager fileExistsAtPath:self.playHistoryFile])
    {
        [self writeHistoryFile:self.playHistoryFile history:[NSArray array]];
    }
    
    return self;
}

- (NSDictionary*)itemParent:(NSDictionary*)item
{
    return [musicFileManager itemForAbsolutePath:
            [[musicFileManager absolutePath:item] stringByDeletingLastPathComponent]];
}


- (bool)item:(NSDictionary*)item1 isEqualToItem:(NSDictionary*)item2
{
    return [[self absolutePath:item1] isEqualToString:[self absolutePath:item2]];
}

#pragma mark - Paths

- (NSString*)absolutePath:(NSDictionary*)item
{
    return [[librariesPath stringByAppendingString:[[item objectForKey:@"player"] objectForKey:@"libraryPath"]]
            stringByAppendingString:[NSString stringWithFormat:@"/%@", [item objectForKey:@"path"]]];
}

- (NSString*)incompleteFileAbsolutePath:(NSDictionary*)musicFile
{
    return [[self absolutePath:musicFile] stringByAppendingString:@".incomplete"];
}

- (NSString*)playPath:(NSDictionary*)musicFile
{
    NSString* path = [self absolutePath:musicFile];
    if ([self.fileManager fileExistsAtPath:path])
    {
        return path;
    }
    
    NSString* incompletePath = [self incompleteFileAbsolutePath:musicFile];
    if ([self.fileManager fileExistsAtPath:incompletePath])
    {
        return incompletePath;
    }
    
    return nil;
}

#pragma mark - State

- (MusicFileState)state:(NSDictionary *)musicFile
{
    MusicFileState state;
    if ([self.fileManager fileExistsAtPath:[self absolutePath:musicFile]])
    {
        state.state = MusicFileBuffered;
    }
    else if (self.bufferingFile && [self item:self.bufferingFile isEqualToItem:musicFile])
    {
        state.state = MusicFileBuffering;
        
        NSString* incompletePath = [self incompleteFileAbsolutePath:musicFile];
        unsigned long long fileSize = 0;
        if ([self.fileManager fileExistsAtPath:incompletePath])
        {
            fileSize = [[self.fileManager attributesOfItemAtPath:incompletePath error:nil] fileSize];
        }
        if (self.bufferingExpectedLength > 0 && fileSize > 0)
        {
            state.buffering.progress = (float)fileSize / (float)self.bufferingExpectedLength;
        }
        else
        {
            state.buffering.progress = 0.0;
        }
        
        state.buffering.isError = self.bufferingIsError;
    }
    else
    {
        state.state = MusicFileNotBuffered;
    }
    return state;
}

#pragma mark - Buffering

- (void)buffer:(NSDictionary*)musicFile
{    
    if (self.bufferingFile)
    {
        if ([[self.bufferingFile objectForKey:@"path"] isEqualToString:[musicFile objectForKey:@"path"]])
        {
            return;
        }
        else
        {            
            [self stopBufferingRequest];
        }
    }
    
    self.bufferingFile = musicFile;
    self.bufferingIsError = false;
    self.bufferingExpectedLength = 0;
    
    [self startBufferingRequest:musicFile];
    [self loadCover:musicFile];
    
    [self notifyStateChanged];
}

- (void)stopBuffering
{
    if (self.bufferingFile)
    {
        [self stopBufferingRequest];
        
        self.bufferingFile = nil;
        self.bufferingIsError = false;
        self.bufferingExpectedLength = 0;
        
        [self notifyStateChanged];
    }
}

- (void)startBufferingRequest:(NSDictionary*)musicFile
{
    [self stopBufferingRequest];
    if (musicFile == nil)
    {
        return;
    }
    
    [self notifyItemPlay:musicFile];
    [self removeOldFiles];
    [self notifyItemPlay:musicFile]; // Again, because previous call can remove our file
    
    NSString* url = [[[musicFile objectForKey:@"player"] objectForKey:@"url"]
                     stringByAppendingString:[NSString stringWithFormat:@"/music/%@", [musicFile objectForKey:@"url"]]];
    self.bufferingRequest = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:url]];
    
    NSString* incompletePath = [self incompleteFileAbsolutePath:musicFile];
    NSString* destinationPath = [self absolutePath:musicFile];
    if ([self.fileManager fileExistsAtPath:incompletePath])
    {
        unsigned long long fileSize = [[self.fileManager attributesOfItemAtPath:incompletePath error:nil] fileSize];
        if (fileSize > 0)
        {
            [self.bufferingRequest addRequestHeader:@"X-Content-Offset" value:[NSString stringWithFormat:@"%llu", fileSize]];
        }
    }
    else
    {
        [self.fileManager createFileAtPath:incompletePath contents:nil attributes:nil];
    }
    
    self.bufferingFileHandle = [NSFileHandle fileHandleForWritingAtPath:incompletePath];
    [self.bufferingFileHandle seekToEndOfFile];
    
    [self.bufferingKeepAliver start];
    
    [self.bufferingRequest setAllowCompressedResponse:NO];
    [self.bufferingRequest setShouldContinueWhenAppEntersBackground:YES];
    [self.bufferingRequest setFailedBlock:^{
        [self onBufferingRequestError];
    }];
    [self.bufferingRequest setHeadersReceivedBlock:^(NSDictionary* responseHeaders){
        if ([self.bufferingRequest responseStatusCode] != 200)
        {
            [self onBufferingRequestError];
        }
        else
        {
            self.bufferingIsError = false;
            self.bufferingExpectedLength = [[responseHeaders objectForKey:@"X-Expected-Content-Length"] intValue];
        }
        
        [self notifyStateChanged];
    }];
    [self.bufferingRequest setDataReceivedBlock:^(NSData* data){
        [self.bufferingFileHandle writeData:data];
        
        [self notifyBufferingProgressFor:self.bufferingFile];
    }];
    [self.bufferingRequest setCompletionBlock:^{
        unsigned long long fileSize = [[self.fileManager attributesOfItemAtPath:incompletePath error:nil] fileSize];
        
        ASIHTTPRequest* sizeRequest = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:url]];
        [sizeRequest setRequestMethod:@"HEAD"];
        [sizeRequest setShouldContinueWhenAppEntersBackground:YES];
        [sizeRequest startSynchronous];
        if (sizeRequest.error || [sizeRequest responseStatusCode] != 200)
        {
            [self onBufferingRequestError];
            return;
        }
        int responseSize = [[[sizeRequest responseHeaders] objectForKey:@"X-Content-Length"] intValue];
        if (fileSize != responseSize)
        {
            if (fileSize > responseSize)
            {
                [self.bufferingFileHandle truncateFileAtOffset:0];
            }
            [self onBufferingRequestError];
            return;
        }
        
        [self stopBufferingRequest];
        
        [self.fileManager moveItemAtPath:incompletePath toPath:destinationPath error:nil];
        
        self.bufferingFile = nil;
        self.bufferingIsError = false;
        self.bufferingExpectedLength = 0;
        
        [self notifyStateChanged];
        [self notifyBufferingCompleted];
    }];
    [self.bufferingRequest startAsynchronous];
}

- (void)onBufferingRequestError
{
    if (!self.bufferingRequest)
    {
        return;
    }
    
    [self stopBufferingRequest];
    
    self.bufferingIsError = true;
    [self performSelector:@selector(startBufferingRequest:) withObject:self.bufferingFile afterDelay:5.0];
    
    [self notifyStateChanged];
}

- (void)stopBufferingRequest
{
    if (self.bufferingRequest)
    {
        [self.bufferingRequest clearDelegatesAndCancel];
        self.bufferingRequest = nil;
    }
    
    if (self.bufferingFileHandle)
    {
        [self.bufferingFileHandle closeFile];
        self.bufferingFileHandle = nil;
    }
    
    [self.bufferingKeepAliver stop];
}

#pragma mark - Cover

- (void)loadCover:(NSDictionary*)musicFile
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString* coverPath = [self coverPath:musicFile];
        if ([self.fileManager fileExistsAtPath:coverPath])
        {
            return;
        }
        
        NSDictionary* album = [self itemParent:musicFile];
        NSString* remoteCoverPath = [album objectForKey:@"cover"];
        
        NSURL* coverUrl = [NSURL URLWithString:
                           [[[musicFile objectForKey:@"player"] objectForKey:@"url"]
                            stringByAppendingString:[NSString stringWithFormat:@"/cover/%@", remoteCoverPath]]];
        ASIHTTPRequest* coverRequest = [ASIHTTPRequest requestWithURL:coverUrl];
        [coverRequest setShouldContinueWhenAppEntersBackground:YES];
        [coverRequest setDownloadDestinationPath:coverPath];
        [coverRequest setTimeOutSeconds:120];
        [coverRequest startSynchronous];
        if ([coverRequest error] || [coverRequest responseStatusCode] != 200)
        {
            [ASIHTTPRequest removeFileAtPath:coverPath error:nil];
        }
        else
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.notificationCenter postNotificationName:@"coverDownloaded" object:self userInfo:nil];
            });
        }
    });
}

- (NSString*)coverPath:(NSDictionary *)musicFile
{
    NSDictionary* parent = [self itemParent:musicFile];
    if (parent == nil)
    {
        return nil;
    }
    
    return [[self absolutePath:parent] stringByAppendingString:@"/cover.jpg"];
}

#pragma mark - Removal

- (void)remove:(NSDictionary*)fileOrDirectory
{
    NSString* removeHistoryWithPrefix = nil;
    NSString* path = [self absolutePath:fileOrDirectory];
    if ([[fileOrDirectory objectForKey:@"type"] isEqualToString:@"directory"])
    {
        NSDirectoryEnumerator* de = [[NSFileManager defaultManager] enumeratorAtPath:path];
        while (true)
        {
            @autoreleasepool
            {
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
                    if ([self canRemoveFile:fileName])
                    {
                        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                    }
                }
            }
        }
        
        removeHistoryWithPrefix = [self absolutePath:fileOrDirectory];
    }
    else
    {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@".incomplete"] error:nil];
        
        BOOL hasAliveSiblingsOrChildren = NO;
        NSString* pathParent = [path stringByDeletingLastPathComponent];
        NSDirectoryEnumerator* de = [[NSFileManager defaultManager] enumeratorAtPath:pathParent];
        while (true)
        {
            @autoreleasepool
            {
                NSString* file = [de nextObject];
                if (!file)
                {
                    break;
                }
                
                NSString* filePath = [[pathParent stringByAppendingString:@"/"] stringByAppendingString:file];
                
                BOOL isDirectory;
                if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory] && !isDirectory)
                {
                    NSString* fileName = [[file pathComponents] lastObject];
                    if ([self canRemoveFile:fileName])
                    {
                        hasAliveSiblingsOrChildren = YES;
                        break;
                    }
                }
            }
        }
        if (!hasAliveSiblingsOrChildren)
        {
            removeHistoryWithPrefix = [[self absolutePath:fileOrDirectory] stringByDeletingLastPathComponent];
        }
    }
    
    if (removeHistoryWithPrefix)
    {
        NSMutableArray* playHistory = [self readHistoryFile:self.playHistoryFile];
        NSMutableIndexSet* playHistoryKeysToDelete = [NSMutableIndexSet indexSet];
        for (int i = 0; i < playHistory.count; i++)
        {
            if ([[self absolutePath:[playHistory objectAtIndex:i]] hasPrefix:removeHistoryWithPrefix])
            {
                [playHistoryKeysToDelete addIndex:i];
            }
        }
        [playHistory removeObjectsAtIndexes:playHistoryKeysToDelete];
        [self writeHistoryFile:self.playHistoryFile history:playHistory];
    }
    
    [self notifyStateChanged];
}

- (BOOL)canRemoveFile:(NSString*)fileName
{
    return !([fileName isEqualToString:@"index.json"] ||
             [fileName isEqualToString:@"index.json.checksum"] ||
             [fileName isEqualToString:@"genres.json"] ||
             [fileName isEqualToString:@"revision.txt"] ||
             [fileName isEqualToString:@"search.json"] ||
             [fileName hasSuffix:@"blacklisted"]);
}

#pragma mark - Internal notifiers

- (void)notifyStateChanged
{
    [self.notificationCenter postNotificationName:@"stateChanged" object:self];
}

- (void)notifyBufferingProgressFor:(NSDictionary*)musicFile
{
    [self.notificationCenter postNotificationName:@"bufferingProgress" object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:musicFile, @"file", nil]];
}

- (void)notifyBufferingCompleted
{
    [self.notificationCenter postNotificationName:@"bufferingCompleted" object:self];
}

#pragma mark - Disk space managment

- (NSMutableArray*)readHistoryFile:(NSString*)path
{
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]
                                           options:NSJSONReadingMutableContainers
                                             error:nil];
}

- (void)writeHistoryFile:(NSString*)path history:(NSArray*)history
{
    [[NSJSONSerialization dataWithJSONObject:history
                                     options:0
                                       error:nil] writeToFile:path atomically:YES];
    [self.notificationCenter postNotificationName:@"historyUpdated" object:self userInfo:nil];
}

- (void)notifyItemAdd:(NSDictionary*)item
{
    [self notifyItem:item historyFile:self.addHistoryFile];
}

- (void)notifyItemPlay:(NSDictionary*)item
{
    if (![musicTableService isDirectory:item])
    {
        item = [self itemParent:item];
        if (item == nil)
        {
            return;
        }
    }
    
    [self notifyItem:item historyFile:self.playHistoryFile];
}

- (void)notifyItem:(NSDictionary*)item historyFile:(NSString*)historyFile
{
    NSMutableArray* history = [self readHistoryFile:historyFile];
    
    bool changed = true;
    while (changed)
    {
        changed = false;
        for (int i = 0; i < history.count; i++)
        {
            NSDictionary* historyItem = [history objectAtIndex:i];
            if (![[NSFileManager defaultManager] fileExistsAtPath:[musicFileManager absolutePath:historyItem]])
            {
                [history removeObjectAtIndex:i];
                changed = true;
                break;
            }
            if ([self item:historyItem isEqualToItem:item])
            {
                [history removeObjectAtIndex:i];
                changed = true;
                break;
            }
        }
    }
    
    [history addObject:item];
    
    [self writeHistoryFile:historyFile history:history];
}

- (NSArray*)listRecentItems
{
    return [[[self readHistoryFile:self.addHistoryFile] reverseObjectEnumerator] allObjects];
}

- (NSArray*)listOldDirectories
{
    return [self readHistoryFile:self.playHistoryFile];
}

- (void)removeOldFiles
{
    while (![self hasFreeSpace])
    {
        NSMutableArray* oldDirectories = [self readHistoryFile:self.playHistoryFile];
        if ([oldDirectories count] > 0)
        {
            NSString* pathToRemove = [self absolutePath:[oldDirectories objectAtIndex:0]];
            
            NSArray* files = [self.fileManager contentsOfDirectoryAtPath:pathToRemove error:nil];
            for (int i = 0; i < [files count]; i++)
            {
                NSString* objectToRemove = [[pathToRemove stringByAppendingString:@"/"]
                                            stringByAppendingString:[files objectAtIndex:i]];
                BOOL isDirectory;
                if ([self.fileManager fileExistsAtPath:objectToRemove isDirectory:&isDirectory] && !isDirectory &&
                    [self canRemoveFile:[files objectAtIndex:i]])
                {
                    [self.fileManager removeItemAtPath:objectToRemove error:nil];
                }
            }
            
            [oldDirectories removeObjectAtIndex:0];
            [self writeHistoryFile:self.playHistoryFile history:oldDirectories];
        }
        else
        {
            break;
        }
    }
}

- (BOOL)hasFreeSpace
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary* sys = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error:nil];
    if (sys)
    {
        unsigned long long totalFreeSpace = [[sys objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
        if (totalFreeSpace < leaveFreeSpace + 200 * 1024 * 1024)
        {
            return NO;
        }
    }
    
    return YES;
}

#pragma mark - Reversing

- (NSString*)navigationPathForItem:(NSDictionary*)item
{
    NSMutableArray* navigationPath = [NSMutableArray array];
    [navigationPath addObject:[item objectForKey:@"name"]];
    
    NSString* basePath = [librariesPath stringByAppendingString:
                          [[item objectForKey:@"player"] objectForKey:@"libraryPath"]];
    NSString* parent = [musicFileManager absolutePath:item];
    while (![(parent = [parent stringByDeletingLastPathComponent]) isEqualToString:basePath])
    {
        NSDictionary* parentItem = [musicFileManager itemForAbsolutePath:parent];
        if (parentItem != nil)
        {
            [navigationPath addObject:[parentItem objectForKey:@"name"]];
        }
    }
    
    return [[[navigationPath reverseObjectEnumerator] allObjects] componentsJoinedByString:@"/"];
}

- (NSDictionary*)itemForAbsolutePath:(NSString*)absolutePath
{
    if (![absolutePath hasPrefix:librariesPath])
    {
        return nil;
    }
    
    NSString* path = [absolutePath substringWithRange:NSMakeRange(librariesPath.length,
                                                                  absolutePath.length - librariesPath.length)];
    
    NSDictionary* player = nil;
    for (int i = 0; i < players.count; i++)
    {
        if ([path hasPrefix:[[[players objectAtIndex:i] objectForKey:@"libraryPath"] stringByAppendingString:@"/"]])
        {
            player = [players objectAtIndex:i];
            break;
        }
    }
    if (!player)
    {
        return nil;
    }
    path = [path substringWithRange:NSMakeRange([[player objectForKey:@"libraryPath"] length] + 1,
                                                path.length - ([[player objectForKey:@"libraryPath"] length] + 1))];

    NSString* parentPath = [path stringByDeletingLastPathComponent];
    NSArray* parentIndex = [musicTableService loadIndexForPlayer:player directory:parentPath];
    for (int i = 0; i < [parentIndex count]; i++)
    {
        NSDictionary* item = [parentIndex objectAtIndex:i];
        if ([[item objectForKey:@"path"] isEqualToString:path])
        {
            return item;
        }
    }
    return nil;
}

@end

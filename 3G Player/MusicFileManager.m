//
//  MusicFileManager.m
//  3G Player
//
//  Created by Admin on 7/4/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "MusicFileManager.h"

#import "Globals.h"

#import "ASIHTTPRequest.h"
#import "JSONKit.h"

@interface MusicFileManager ()

@property (nonatomic, retain) NSFileManager*        fileManager;
@property (nonatomic, retain) NSNotificationCenter* notificationCenter;

@property (nonatomic, retain) NSDictionary*     bufferingFile;
@property (nonatomic)         bool              bufferingIsError;
@property (nonatomic)         uint              bufferingExpectedLength;

@property (nonatomic, retain) ASIHTTPRequest*   bufferingRequest;
@property (nonatomic, retain) NSFileHandle*     bufferingFileHandle;

@property (nonatomic, retain) NSString*         historyFile;

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
    
    self.historyFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/history.json"];
    if (![self.fileManager fileExistsAtPath:self.historyFile])
    {
        NSMutableDictionary* history = [NSMutableDictionary dictionary];
        NSDirectoryEnumerator* de = [[NSFileManager defaultManager] enumeratorAtPath:libraryDirectory];
        while (true)
        {
            @autoreleasepool
            {
                NSString* file = [de nextObject];
                if (!file)
                {
                    break;
                }
                
                NSString* filePath = [[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:file];
                
                BOOL isDirectory;
                if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory] && !isDirectory)
                {
                    NSString* fileName = [[file pathComponents] lastObject];
                    if ([self isMusicFile:fileName])
                    {
                        NSDictionary* attributes = [self.fileManager attributesOfItemAtPath:filePath error:nil];
                        [history setValue:[NSNumber numberWithInt:[[attributes objectForKey:NSFileCreationDate] timeIntervalSince1970]] forKey:[self musicHistoryKey:file]];
                    }
                }
            }
        }
        [self writeHistoryFile:history];
    }
    
    return self;
}

- (MusicFileState)getState:(NSDictionary*)musicFile
{
    MusicFileState state;
    if ([self.fileManager fileExistsAtPath:[self filePath:musicFile]])
    {
        state.state = MusicFileBuffered;
    }
    else if (self.bufferingFile && [[self.bufferingFile objectForKey:@"path"] isEqualToString:[musicFile objectForKey:@"path"]])
    {
        state.state = MusicFileBuffering;
        
        NSString* incompletePath = [self incompleteFilePath:musicFile];
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

- (NSString*)getPath:(NSDictionary*)musicFile
{
    NSString* path = [self filePath:musicFile];
    if ([self.fileManager fileExistsAtPath:path])
    {
        return path;
    }
    
    NSString* incompletePath = [self incompleteFilePath:musicFile];
    if ([self.fileManager fileExistsAtPath:incompletePath])
    {
        return incompletePath;
    }
    
    return nil;
}

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
    
    [self notifyFileUsage:musicFile];
    [self removeOldFiles];
    [self notifyFileUsage:musicFile];
    
    NSString* url = [[playerUrl stringByAppendingString:@"/file?path="] stringByAppendingString:[musicFile objectForKey:@"url"]];
    NSString* sizeUrl = [[playerUrl stringByAppendingString:@"/file_size?path="] stringByAppendingString:[musicFile objectForKey:@"url"]];
    NSString* incompletePath = [self incompleteFilePath:musicFile];
    NSString* destinationPath = [self filePath:musicFile];
    if ([self.fileManager fileExistsAtPath:incompletePath])
    {
        unsigned long long fileSize = [[self.fileManager attributesOfItemAtPath:incompletePath error:nil] fileSize];
        if (fileSize > 0)
        {
            url = [url stringByAppendingFormat:@"&content_offset=%llu", fileSize];
        }
    }
    else
    {
        [self.fileManager createFileAtPath:incompletePath contents:nil attributes:nil];
    }
    
    self.bufferingFileHandle = [NSFileHandle fileHandleForWritingAtPath:incompletePath];
    [self.bufferingFileHandle seekToEndOfFile];
    
    self.bufferingRequest = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:url]];
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
        
        ASIHTTPRequest* sizeRequest = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:sizeUrl]];
        [sizeRequest setAllowCompressedResponse:NO];
        [sizeRequest setShouldContinueWhenAppEntersBackground:YES];
        [sizeRequest startSynchronous];
        if (sizeRequest.error || [sizeRequest responseStatusCode] != 200)
        {
            [self onBufferingRequestError];
            return;
        }
        int responseSize = [[sizeRequest responseString] intValue];
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
}

- (void)loadCover:(NSDictionary*)musicFile
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString* coverPath = [self coverPath:musicFile];
        if ([self.fileManager fileExistsAtPath:coverPath])
        {
            return;
        }
        
        NSDictionary* album = [self itemByPath:[[musicFile objectForKey:@"path"]
                                                stringByDeletingLastPathComponent]];
        NSString* remoteCoverPath = [album objectForKey:@"cover"];
        
        NSURL* coverUrl = [NSURL URLWithString:
                           [playerUrl stringByAppendingString:
                            [NSString stringWithFormat:@"/cover?path=%@", remoteCoverPath, nil]]];
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
    return [[[self filePath:musicFile]
             stringByDeletingLastPathComponent]
            stringByAppendingString:@"/cover.jpg"];
}

- (void)deleteFileOrdirectory:(NSDictionary*)fileOrDirectory
{
    NSString* removeHistoryWithPrefix = nil;
    NSString* path = [[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[fileOrDirectory objectForKey:@"path"]];
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
                    if ([self isMusicFile:fileName])
                    {
                        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                    }
                }
            }
        }
        
        removeHistoryWithPrefix = [fileOrDirectory objectForKey:@"path"];
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
                    if ([self isMusicFile:fileName])
                    {
                        hasAliveSiblingsOrChildren = YES;
                        break;
                    }
                }
            }
        }
        if (!hasAliveSiblingsOrChildren)
        {
            removeHistoryWithPrefix = [[fileOrDirectory objectForKey:@"path"] stringByDeletingLastPathComponent];
        }
    }
    
    if (removeHistoryWithPrefix)
    {
        NSMutableDictionary* history = [self readHistoryFile];
        NSMutableArray* historyKeysToDelete = [NSMutableArray array];
        for (NSString* key in [history keyEnumerator])
        {
            if ([key hasPrefix:removeHistoryWithPrefix])
            {
                [historyKeysToDelete addObject:key];
            }
        }
        [history removeObjectsForKeys:historyKeysToDelete];
        [self writeHistoryFile:history];
    }
    
    [self notifyStateChanged];
}

#pragma mark - Internals

- (NSString*)filePath:(NSDictionary*)musicFile
{
    return [[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[musicFile objectForKey:@"path"]];
}

- (NSString*)incompleteFilePath:(NSDictionary*)musicFile
{
    return [[self filePath:musicFile] stringByAppendingString:@".incomplete"];
}

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

- (BOOL)isMusicFile:(NSString*)fileName
{
    return !([fileName isEqualToString:@"index.json"] ||
             [fileName isEqualToString:@"index.json.checksum"] ||
             [fileName isEqualToString:@"revision.txt"] ||
             [fileName hasSuffix:@"blacklisted"]);
}

- (NSString*)musicHistoryKey:(NSString*)path
{
    NSMutableArray* pathComponents = [[path pathComponents] mutableCopy];
    [pathComponents removeLastObject];
    return [pathComponents componentsJoinedByString:@"/"];
}

- (NSMutableDictionary*)readHistoryFile
{
    return [[JSONDecoder decoder] mutableObjectWithData:[NSData dataWithContentsOfFile:self.historyFile]];
}

- (void)writeHistoryFile:(NSMutableDictionary*)history
{
    [[history JSONData] writeToFile:self.historyFile atomically:YES];
    [self.notificationCenter postNotificationName:@"historyUpdated" object:self userInfo:nil];
}

- (void)notifyFileUsage:(NSDictionary*)musicFile
{
    NSMutableDictionary* history = [self readHistoryFile];
    [history setValue:[NSNumber numberWithInt:(int)time(NULL)] forKey:[self musicHistoryKey:[musicFile objectForKey:@"path"]]];
    [self writeHistoryFile:history];
}

- (NSArray*)listOldDirectories
{
    return [[self readHistoryFile] keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2){
        return [obj1 compare:obj2];
    }];
}

- (void)removeOldFiles
{
    while (![self hasFreeSpace])
    {
        NSArray* oldDirectories = [self listOldDirectories];
        if ([oldDirectories count] > 0)
        {
            NSString* directoryToRemove = [[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[oldDirectories objectAtIndex:0]];
            
            NSArray* files = [self.fileManager contentsOfDirectoryAtPath:directoryToRemove error:nil];
            for (int i = 0; i < [files count]; i++)
            {
                NSString* objectToRemove = [[directoryToRemove stringByAppendingString:@"/"] stringByAppendingString:[files objectAtIndex:i]];
                BOOL isDirectory;
                if ([self.fileManager fileExistsAtPath:objectToRemove isDirectory:&isDirectory] && !isDirectory &&
                    [self isMusicFile:[files objectAtIndex:i]])
                {
                    [self.fileManager removeItemAtPath:objectToRemove error:nil];
                }
            }
            
            NSMutableDictionary* history = [self readHistoryFile];
            [history removeObjectForKey:[oldDirectories objectAtIndex:0]];
            [self writeHistoryFile:history];
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
        if (totalFreeSpace < (200 + freeSpaceMb) * 1024 * 1024)
        {
            return NO;
        }
    }
    
    return YES;
}

- (NSArray*)pathForDirectory:(NSString*)directory
{
    NSArray* parts = [directory componentsSeparatedByString:@"/"];
    NSMutableArray* path = [NSMutableArray array];
    for (int j = 0; j < [parts count]; j++)
    {
        NSString* indexJsonPath = [[[libraryDirectory stringByAppendingString:@"/"]
                                    stringByAppendingString:[[parts subarrayWithRange:NSMakeRange(0, j)]
                                                             componentsJoinedByString:@"/"]]
                                   stringByAppendingString:@"/index.json"];
        NSDictionary* index = [[JSONDecoder decoder] objectWithData:[NSData dataWithContentsOfFile:indexJsonPath]];
        NSDictionary* pathPart = nil;
        NSString* pathPartPath = [[parts subarrayWithRange:NSMakeRange(0, j + 1)]
                                  componentsJoinedByString:@"/"];
        for (NSString* key in index)
        {
            NSDictionary* probablePathPart = [index objectForKey:key];
            if ([[probablePathPart objectForKey:@"path"] isEqualToString:pathPartPath])
            {
                pathPart = probablePathPart;
            }
        }
        if (pathPart)
        {
            [path addObject:[pathPart objectForKey:@"name"]];
        }
        else
        {
            return nil;
        }
    }
    return parts;
}

- (NSDictionary*)itemByPath:(NSString*)path
{
    if ([path isEqualToString:@""])
    {
        return nil;
    }
    
    NSString* parentPath = [path stringByDeletingLastPathComponent];
    NSArray* parentIndex = [musicTableService loadIndexFor:parentPath];
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

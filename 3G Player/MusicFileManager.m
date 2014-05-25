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
    
    [self notifyFileUsage:musicFile];
    [self removeOldFiles];
    [self notifyFileUsage:musicFile];
    
    NSString* url = [[playerUrl stringByAppendingString:@"/file?path="] stringByAppendingString:[musicFile objectForKey:@"url"]];
    NSString* sizeUrl = [[playerUrl stringByAppendingString:@"/file_size?path="] stringByAppendingString:[musicFile objectForKey:@"url"]];
    NSString* incompletePath = [self incompleteFilePath:musicFile];
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
        if (sizeRequest.error || [sizeRequest responseStatusCode] != 200 ||
            ![[NSString stringWithFormat:@"%llu", fileSize] isEqualToString:[sizeRequest responseString]])
        {
            [self onBufferingRequestError];
            return;
        }
        
        [self stopBufferingRequest];
        
        [self.fileManager moveItemAtPath:incompletePath toPath:[self filePath:self.bufferingFile] error:nil];
        
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

- (void)deleteFileOrdirectory:(NSDictionary*)fileOrDirectory
{
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
    }
    else
    {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@".incomplete"] error:nil];
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

- (NSString*)musicHistoryKey:(NSString*) path
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
    [self.notificationCenter postNotificationName:@"oldDirectoriesUpdated" object:self userInfo:nil];
}

- (void)notifyFileUsage:(NSDictionary*)musicFile
{
    NSMutableDictionary* history = [self readHistoryFile];
    [history setValue:[NSNumber numberWithInt:time(NULL)] forKey:[self musicHistoryKey:[musicFile objectForKey:@"path"]]];
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
        if (totalFreeSpace < 300 * 1024 * 1024)
        {
            return NO;
        }
    }
    
    return YES;
}

@end

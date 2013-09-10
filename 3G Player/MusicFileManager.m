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

@interface MusicFileManager ()

@property (nonatomic, retain) NSFileManager*        fileManager;
@property (nonatomic, retain) NSNotificationCenter* notificationCenter;

@property (nonatomic, retain) NSDictionary*     bufferingFile;
@property (nonatomic)         bool              bufferingIsError;
@property (nonatomic)         uint              bufferingExpectedLength;

@property (nonatomic, retain) ASIHTTPRequest*   bufferingRequest;
@property (nonatomic, retain) NSFileHandle*     bufferingFileHandle;

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
        [self.bufferingRequest cancel];
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
                    if (!([fileName isEqualToString:@"index.json"] || [fileName isEqualToString:@"index.json.checksum"]))
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

@end

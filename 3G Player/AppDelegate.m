//
//  AppDelegate.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "AppDelegate.h"

#import "CocoaAsyncSocket/GCDAsyncSocket.h"

#import "Globals.h"

@implementation AppDelegate

GCDAsyncSocket* serverSocket;
dispatch_queue_t serverSocketQueue;

- (void)dealloc
{
    [_window release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    application.idleTimerDisabled = YES;
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    
    [self registerDefaultsFromSettingsBundle];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(readDefaults) name:NSUserDefaultsDidChangeNotification object:nil];
    [self readDefaults];
    
    libraryDirectory = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/Library"];
    [[NSFileManager defaultManager] createDirectoryAtPath:libraryDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [libraryDirectory retain];
    
    musicFileManager = [[MusicFileManager alloc] init];
    scrobbler = [[Scrobbler alloc] init];
    
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    
    self.tabBarController = [[UITabBarController alloc] init];
    
    controllers.current = [[CurrentController alloc] init];
    [self.tabBarController addChildViewController:controllers.current];
    
    controllers.library = [[LibraryController alloc] initWithRoot];
    [self.tabBarController addChildViewController:controllers.library];
    
    controllers.info = [[InfoController alloc] init];
    [self.tabBarController addChildViewController:controllers.info];
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    
    serverSocketQueue = dispatch_queue_create("serverSocketQueue", NULL);
    [self initServerSocket];
    
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = self.tabBarController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)readDefaults
{   
    playerUrl = [[NSUserDefaults standardUserDefaults] stringForKey:@"player_url"];
    [playerUrl retain];
    
    lastfmUsername = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastfm_username"];
    [lastfmUsername retain];
    
    lastfmPassword = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastfm_password"];
    [lastfmPassword retain];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [serverSocket setDelegate:nil];
    [serverSocket disconnect];
    [serverSocket dealloc];
    serverSocket = nil;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [self initServerSocket];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)initServerSocket
{
    serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:controllers.current delegateQueue:serverSocketQueue];
    [serverSocket acceptOnPort:20139 error:nil];
}

#pragma mark - Remote Control Buttons delegate

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)remoteControlReceivedWithEvent:(UIEvent*)receivedEvent
{
    if (receivedEvent.type == UIEventTypeRemoteControl)
    {
        switch (receivedEvent.subtype)
        {
            case UIEventSubtypeRemoteControlPlay:
                [controllers.current.player play];
                break;
                
            case UIEventSubtypeRemoteControlPause:
                [controllers.current pause];
                break;
                
            case UIEventSubtypeRemoteControlPreviousTrack:
                [controllers.current playPrevTrack:FALSE];
                break;
                
            case UIEventSubtypeRemoteControlNextTrack:
                [controllers.current playNextTrack:FALSE];
                break;
                
            default:
                break;
        }
    }
}

// Why am I supposed to do this?
- (void)registerDefaultsFromSettingsBundle
{
    NSString* settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    if (!settingsBundle)
    {
        return;
    }
    
    NSDictionary* settings = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray* preferences = [settings objectForKey:@"PreferenceSpecifiers"];
    
    NSMutableDictionary* defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];
    for (NSDictionary* prefSpecification in preferences)
    {
        NSString* key = [prefSpecification objectForKey:@"Key"];
        if (key)
        {
            [defaultsToRegister setObject:[prefSpecification objectForKey:@"DefaultValue"] forKey:key];
        }
    }
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsToRegister];
    [defaultsToRegister release];
}

@end

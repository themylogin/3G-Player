//
//  AppDelegate.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "AppDelegate.h"

#import "Globals.h"

@implementation AppDelegate

- (void)dealloc
{
    [_window release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    [self registerDefaultsFromSettingsBundle];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(readDefaults) name:NSUserDefaultsDidChangeNotification object:nil];
    [self readDefaults];
    
    libraryDirectory = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/Library"];
    [libraryDirectory retain];
    
    musicFileManager = [[MusicFileManager alloc] init];
    scrobbler = [[Scrobbler alloc] init];
    
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    
    self.tabBarController = [[UITabBarController alloc] init];
    
    controllers.playlist = [[PlaylistController alloc] init];
    [self.tabBarController addChildViewController:controllers.playlist];
    
    controllers.library = [[LibraryController alloc] init];
    [self.tabBarController addChildViewController:controllers.library];
    
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = self.tabBarController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)readDefaults
{   
    playerUrl = @"http://plr.thelogin.ru";
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
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
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

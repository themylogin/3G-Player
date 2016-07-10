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
    
    [self setupApplication];
    
    return YES;
}

- (void)setupApplication
{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    
    librariesPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]
                     stringByAppendingString:@"/Libraries"];
    [librariesPath retain];
    
    [self registerDefaultsFromSettingsBundle];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(readSettings)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    [self readSettings];
    
    if (!([players count] > 0))
    {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        exit(0);
    }
    
    musicTableService = [[MusicTableService alloc] init];
    musicFileManager = [[MusicFileManager alloc] init];
    scrobbler = [[Scrobbler alloc] init];
    recommendationsUtils = [[RecommendationsUtils alloc] init];
    
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    
    controllers.tabBar = [[UITabBarController alloc] init];
    self.tabBarController = controllers.tabBar;
    
    controllers.current = [[CurrentController alloc] init];
    [self.tabBarController addChildViewController:controllers.current];
    
    controllers.library = [[LibraryController alloc] initWithPlayer:[players objectAtIndex:0]];
    [self.tabBarController addChildViewController:controllers.library];
    
    controllers.recents = [[RecentsController alloc] init];
    [self.tabBarController addChildViewController:controllers.recents];
    
    controllers.info = [[InfoController alloc] init];
    [self.tabBarController addChildViewController:controllers.info];
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    
    serverSocketQueue = dispatch_queue_create("serverSocketQueue", NULL);
    [self initServerSocket];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = self.tabBarController;
    [self.window makeKeyAndVisible];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // [serverSocket setDelegate:nil];
    // [serverSocket disconnect];
    // [serverSocket dealloc];
    // serverSocket = nil;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // [self initServerSocket];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    [musicFileManager removeOldFiles];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
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
                
            case UIEventSubtypeRemoteControlBeginSeekingBackward:
            case UIEventSubtypeRemoteControlEndSeekingBackward:
            case UIEventSubtypeRemoteControlBeginSeekingForward:
            case UIEventSubtypeRemoteControlEndSeekingForward:
                [controllers.current handleSeeking:receivedEvent.subtype];
                break;
                
            default:
                break;
        }
    }
}

#pragma mark - Settings

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

- (void)readSettings
{
    NSMutableArray* mutablePlayers = [NSMutableArray array];
    for (int i = 1; i <= 5; i++)
    {
        NSString* stringUrl = [[NSUserDefaults standardUserDefaults] stringForKey:
                               [NSString stringWithFormat:@"Player%d_URL", i]];
        NSURL* url = [NSURL URLWithString:stringUrl];
        if (url && [url host])
        {
            NSString* libraryPath = [NSString stringWithFormat:@"/%@", [url host]];
            
            [[NSFileManager defaultManager]
             createDirectoryAtPath:[librariesPath stringByAppendingString:libraryPath]
             withIntermediateDirectories:YES
             attributes:nil
             error:nil];
            
            NSMutableArray* lastFmUsernames = [NSMutableArray array];
            for (int j = 1; j <= 2; j++)
            {
                NSString* _lastFmUsername = [[NSUserDefaults standardUserDefaults] stringForKey:
                                             [NSString stringWithFormat:@"Player%d_LastFM_Username%d", i, j]];
                if (_lastFmUsername)
                {
                    _lastFmUsername = [_lastFmUsername stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (![_lastFmUsername isEqualToString:@""])
                    {
                        [lastFmUsernames addObject:_lastFmUsername];
                    }
                }
            }
            
            [mutablePlayers addObject:@{@"lastFmUsernames": lastFmUsernames,
                                        @"libraryPath": libraryPath,
                                        @"name": [url host],
                                        @"url": stringUrl}];
        }
    }
    players = [NSArray arrayWithArray:mutablePlayers];
    [players retain];
    
    leaveFreeSpace = [[NSUserDefaults standardUserDefaults] integerForKey:@"LeaveFreeSpaceMb"] * 1024 * 1024;
    
    lastFmUsername = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastFM_Username"];
    [lastFmUsername retain];
    
    lastFmPassword = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastFM_Password"];
    [lastFmPassword retain];
}

#pragma mark - Remote control

- (void)initServerSocket
{
    serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:controllers.current delegateQueue:serverSocketQueue];
    [serverSocket performBlock:^{
        [serverSocket enableBackgroundingOnSocket];
    }];
    [serverSocket acceptOnPort:20139 error:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    
    CGRect keyboardFrameEnd = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrameEnd = [self.tabBarController.view convertRect:keyboardFrameEnd fromView:nil];

    [UIView
     animateWithDuration:duration
     delay:0
     options:UIViewAnimationOptionBeginFromCurrentState | curve
     animations:^{
         CGRect frame = CGRectMake(0, 0, keyboardFrameEnd.size.width, keyboardFrameEnd.origin.y);
         self.tabBarController.view.frame = frame;
         [[controllers.library viewControllers] lastObject].view.frame = frame;
     }
     completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    
    CGRect keyboardFrameEnd = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrameEnd = [self.tabBarController.view convertRect:keyboardFrameEnd fromView:nil];
    
    [UIView
     animateWithDuration:duration
     delay:0
     options:UIViewAnimationOptionBeginFromCurrentState | curve
     animations:^{
         CGRect frame = CGRectMake(0, 0, keyboardFrameEnd.size.width, keyboardFrameEnd.origin.y);
         self.tabBarController.view.frame = frame;
         [[controllers.library viewControllers] lastObject].view.frame = frame;
     }
     completion:^(BOOL _){
         CGRect frame = CGRectMake(0, 0, keyboardFrameEnd.size.width, keyboardFrameEnd.origin.y);
         [[controllers.library viewControllers] lastObject].view.frame = frame;
     }];
}

@end
